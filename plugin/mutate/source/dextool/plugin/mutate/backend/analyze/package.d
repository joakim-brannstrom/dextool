/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

#SPC-analyzer

TODO cache the checksums. They are *heavy*.
*/
module dextool.plugin.mutate.backend.analyze;

import logger = std.experimental.logger;
import std.algorithm : map, filter, joiner, cache;
import std.array : array, appender;
import std.concurrency;
import std.datetime : dur;
import std.exception : collectException;
import std.parallelism;
import std.range : tee;
import std.typecons;

import colorlog;

import dextool.compilation_db : CompileCommandFilter, defaultCompilerFlagFilter,
    CompileCommandDB, SearchResult;
import dextool.plugin.mutate.backend.analyze.internal : Cache, TokenStream;
import dextool.plugin.mutate.backend.database : Database, LineMetadata, MutationPointEntry2;
import dextool.plugin.mutate.backend.database.type : MarkedMutant;
import dextool.plugin.mutate.backend.diff_parser : Diff;
import dextool.plugin.mutate.backend.interface_ : ValidateLoc, FilesysIO;
import dextool.plugin.mutate.backend.report.utility : statusToString, Table;
import dextool.plugin.mutate.backend.utility : checksum, trustedRelativePath, Checksum;
import dextool.plugin.mutate.backend.utility : getProfileResult, Profile;
import dextool.plugin.mutate.config : ConfigCompiler, ConfigAnalyze;
import dextool.set;
import dextool.type : ExitStatusType, AbsolutePath, Path;
import dextool.user_filerange;

version (unittest) {
    import unit_threaded.assertions;
}

/** Analyze the files in `frange` for mutations.
 */
ExitStatusType runAnalyzer(ref Database db, ConfigAnalyze conf_analyze,
        ConfigCompiler conf_compiler, UserFileRange frange, ValidateLoc val_loc, FilesysIO fio) @trusted {
    import dextool.plugin.mutate.backend.diff_parser : diffFromStdin, Diff;

    auto fileFilter = () {
        try {
            return FileFilter(fio.getOutputDir, conf_analyze.unifiedDiffFromStdin,
                    conf_analyze.unifiedDiffFromStdin ? diffFromStdin : Diff.init);
        } catch (Exception e) {
            logger.info(e.msg);
            logger.warning("Unable to parse diff");
        }
        return FileFilter.init;
    }();

    auto pool = () {
        if (conf_analyze.poolSize == 0)
            return new TaskPool();
        return new TaskPool(conf_analyze.poolSize);
    }();

    // will only be used by one thread at a time.
    auto store = spawn(&storeActor, cast(shared)&db, cast(shared) fio.dup,
            conf_analyze.prune, conf_analyze.fastDbStore, conf_analyze.poolSize);

    int taskCnt;
    Set!AbsolutePath alreadyAnalyzed;
    // dfmt off
    foreach (f; frange.filter!(a => !a.isNull)
            .map!(a => a.get)
            // The tool only supports analyzing a file one time.
            // This optimize it in some cases where the same file occurs
            // multiple times in the compile commands database.
            .filter!(a => a.absoluteFile !in alreadyAnalyzed)
            .tee!(a => alreadyAnalyzed.add(a.absoluteFile))
            .cache
            .filter!(a => !isPathInsideAnyRoot(conf_analyze.exclude, a.absoluteFile))
            .filter!(a => fileFilter.shouldAnalyze(a.absoluteFile))) {
        try {
            pool.put(task!analyzeActor(f, val_loc.dup, fio.dup, conf_compiler, store));
            taskCnt++;
        } catch (Exception e) {
            logger.trace(e);
            logger.warning(e.msg);
        }
    }
    // dfmt on

    // inform the store actor of how many analyse results it should *try* to
    // save.
    send(store, AnalyzeCntMsg(taskCnt));
    // wait for all files to be analyzed
    pool.finish(true);
    // wait for the store actor to finish
    receiveOnly!StoreDoneMsg;

    if (conf_analyze.profile)
        try {
            import std.stdio : writeln;

            writeln(getProfileResult.toString);
        } catch (Exception e) {
            logger.warning("Unable to print the profile data: ", e.msg).collectException;
        }

    return ExitStatusType.Ok;
}

@safe:

/** Filter function for files. Either all or those in stdin.
 *
 * The matching ignores the file extension in order to lessen the problem of a
 * file that this approach skip headers because they do not exist in
 * `compile_commands.json`. It means that e.g. "foo.hpp" would match `true` if
 * `foo.cpp` is in `compile_commands.json`.
 */
struct FileFilter {
    import std.path : stripExtension;

    Set!string files;
    bool useFileFilter;
    AbsolutePath root;

    this(AbsolutePath root, bool fromStdin, Diff diff) {
        this.root = root;
        this.useFileFilter = fromStdin;
        foreach (a; diff.toRange(root)) {
            files.add(a.key.stripExtension);
        }
    }

    bool shouldAnalyze(AbsolutePath p) {
        import std.path : relativePath;

        if (!useFileFilter) {
            return true;
        }

        return relativePath(p, root).stripExtension in files;
    }
}

/// Number of analyze tasks that has been spawned that the `storeActor` should wait for.
struct AnalyzeCntMsg {
    int value;
}

struct StoreDoneMsg {
}

/// Start an analyze of a file
void analyzeActor(SearchResult fileToAnalyze, ValidateLoc vloc, FilesysIO fio,
        ConfigCompiler conf, Tid storeActor) @trusted nothrow {
    auto profile = Profile("analyze file " ~ fileToAnalyze.absoluteFile);

    try {
        auto analyzer = Analyze(vloc, fio, conf.forceSystemIncludes);
        analyzer.process(fileToAnalyze);
        send(storeActor, cast(immutable) analyzer.result);
        return;
    } catch (Exception e) {
    }

    // send a dummy result
    try {
        send(storeActor, cast(immutable) new Analyze.Result);
    } catch (Exception e) {
    }
}

/// Store the result of the analyze.
void storeActor(scope shared Database* dbShared, scope shared FilesysIO fioShared,
        const bool prune, const bool fastDbStore, const long poolSize) @trusted nothrow {
    import dextool.plugin.mutate.backend.database : LineMetadata, FileId, LineAttr, NoMut;
    import cachetools : CacheLRU;
    import dextool.cachetools : nullableCache;

    Database* db = cast(Database*) dbShared;
    FilesysIO fio = cast(FilesysIO) fioShared;

    // A file is at most saved one time to the database.
    Set!Path savedFiles;

    auto getFileId = nullableCache!(string, FileId, (string p) => db.getFileId(p.Path))(256,
            30.dur!"seconds");
    auto getFileDbChecksum = nullableCache!(string, Checksum,
            (string p) => db.getFileChecksum(p.Path))(256, 30.dur!"seconds");
    auto getFileFsChecksum = nullableCache!(string, Checksum, (string p) {
        return checksum(fio.makeInput(AbsolutePath(Path(p))).content[]);
    })(256, 30.dur!"seconds");

    static struct Files {
        Checksum[Path] value;

        this(ref Database db) {
            foreach (a; db.getDetailedFiles) {
                value[a.file] = a.fileChecksum;
            }
        }
    }

    void save(immutable Analyze.Result result) {
        // mark files that have an unchanged checksum as "already saved"
        foreach (f; result.idFile
                .byKey
                .filter!(a => a !in savedFiles)
                .filter!(a => getFileDbChecksum(fio.toRelativeRoot(a)) == getFileFsChecksum(a))) {
            logger.info("Unchanged ".color(Color.yellow), f);
            savedFiles.add(f);
        }

        // only saves mutation points to a file one time.
        {
            auto app = appender!(MutationPointEntry2[])();
            foreach (mp; result.mutationPoints // remove those that has been globally saved
                .filter!(a => a.file !in savedFiles)) {
                app.put(mp);
            }
            foreach (f; result.idFile.byKey.filter!(a => a !in savedFiles)) {
                logger.info("Saving ".color(Color.green), f);
                db.removeFile(fio.toRelativeRoot(f));
                const info = result.infoId[result.idFile[f]];
                db.put(fio.toRelativeRoot(f), info.checksum, info.language);
                savedFiles.add(f);
            }
            db.put(app.data, fio.getOutputDir);
        }

        {
            Set!long printed;
            auto app = appender!(LineMetadata[])();
            foreach (md; result.metadata) {
                // transform the ID from local to global.
                const fid = getFileId(fio.toRelativeRoot(result.fileId[md.id]));
                if (fid.isNull && !printed.contains(md.id)) {
                    printed.add(md.id);
                    logger.warningf("File with suppressed mutants (// NOMUT) not in the database: %s. Skipping...",
                            result.fileId[md.id]).collectException;
                    continue;
                }
                app.put(LineMetadata(fid.get, md.line, md.attr));
            }
            db.put(app.data);
        }
    }

    // listen for results from workers until the expected number is processed.
    void recv() {
        auto profile = Profile("updating files");
        logger.info("Updating files");

        int resultCnt;
        Nullable!int maxResults;
        bool running = true;

        while (running) {
            try {
                receive((AnalyzeCntMsg a) { maxResults = a.value; }, (immutable Analyze.Result a) {
                    resultCnt++;
                    save(a);
                },);
            } catch (Exception e) {
                logger.trace(e).collectException;
                logger.warning(e.msg).collectException;
            }

            if (!maxResults.isNull && resultCnt >= maxResults.get) {
                running = false;
            }
        }
    }

    void pruneFiles() {
        import std.path : buildPath;

        auto profile = Profile("prune files");

        logger.info("Pruning the database of dropped files");
        auto files = db.getFiles.map!(a => buildPath(fio.getOutputDir, a).Path).toSet;

        foreach (f; files.setDifference(savedFiles).toRange) {
            logger.info("Removing ".color(Color.red), f);
            db.removeFile(fio.toRelativeRoot(f));
        }
    }

    void fastDbOn() {
        if (!fastDbStore)
            return;
        logger.info(
                "Turning OFF sqlite3 synchronization protection to improve the write performance");
        logger.warning("Do NOT interrupt dextool in any way because it may corrupt the database");
        db.run("PRAGMA synchronous = OFF");
        db.run("PRAGMA journal_mode = MEMORY");
    }

    void fastDbOff() {
        if (!fastDbStore)
            return;
        db.run("PRAGMA synchronous = ON");
        db.run("PRAGMA journal_mode = DELETE");
    }

    try {
        import dextool.plugin.mutate.backend.test_mutant.timeout : resetTimeoutContext;

        // by making the mailbox size follow the number of workers the overall
        // behavior will slow down if saving to the database is too slow. This
        // avoids excessive or even fatal memory usage.
        setMaxMailboxSize(thisTid, poolSize + 2, OnCrowding.block);

        fastDbOn();

        auto trans = db.transaction;

        // TODO: only remove those files that are modified.
        logger.info("Removing metadata");
        db.clearMetadata;

        recv();

        // TODO: print what files has been updated.
        logger.info("Resetting timeout context");
        resetTimeoutContext(*db);

        logger.info("Updating metadata");
        db.updateMetadata;

        if (prune) {
            pruneFiles();
            auto profile = Profile("remove orphant mutants");
            logger.info("Removing orphant mutants");
            db.removeOrphanedMutants;
        }

        logger.info("Updating manually marked mutants");
        updateMarkedMutants(*db);
        printLostMarkings(db.getLostMarkings);

        logger.info("Committing changes");
        trans.commit;
        logger.info("Ok".color(Color.green));

        fastDbOff();
    } catch (Exception e) {
        logger.error(e.msg).collectException;
    }

    try {
        send(ownerTid, StoreDoneMsg.init);
    } catch (Exception e) {
        logger.errorf("Fatal error. Unable to send %s to the main thread",
                StoreDoneMsg.init).collectException;
    }
}

/// Analyze a file for mutants.
struct Analyze {
    import std.regex : Regex, regex, matchFirst;
    import std.typecons : NullableRef, Nullable, Yes;
    import miniorm : Transaction;
    import cpptooling.analyzer.clang.context : ClangContext;
    import cpptooling.utility.virtualfilesystem;
    import dextool.compilation_db : SearchResult;
    import dextool.type : Exists, makeExists;
    import dextool.utility : analyzeFile;

    private {
        static immutable raw_re_nomut = `^((//)|(/\*))\s*NOMUT\s*(\((?P<tag>.*)\))?\s*((?P<comment>.*)\*/|(?P<comment>.*))?`;

        Regex!char re_nomut;

        ValidateLoc val_loc;
        FilesysIO fio;
        bool forceSystemIncludes;

        Cache cache;

        Result result;
    }

    this(ValidateLoc val_loc, FilesysIO fio, bool forceSystemIncludes) @trusted {
        this.val_loc = val_loc;
        this.fio = fio;
        this.cache = new Cache;
        this.re_nomut = regex(raw_re_nomut);
        this.forceSystemIncludes = forceSystemIncludes;
        this.result = new Result;
    }

    void process(SearchResult in_file) @safe {
        in_file.flags.forceSystemIncludes = forceSystemIncludes;

        // find the file and flags to analyze
        Exists!AbsolutePath checked_in_file;
        try {
            checked_in_file = makeExists(in_file.absoluteFile);
        } catch (Exception e) {
            logger.warning(e.msg);
            return;
        }

        try {
            () @trusted {
                auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
                auto tstream = new TokenStreamImpl(ctx);

                analyzeForMutants(in_file, checked_in_file, ctx, tstream);
                // TODO: filter files so they are only analyzed once for comments
                foreach (f; result.fileId.byValue)
                    analyzeForComments(f, tstream);
            }();
        } catch (Exception e) {
            () @trusted { logger.trace(e); }();
            logger.info(e.msg);
            logger.error("failed analyze of ", in_file).collectException;
        }
    }

    void analyzeForMutants(SearchResult in_file,
            Exists!AbsolutePath checked_in_file, ref ClangContext ctx, TokenStream tstream) @safe {
        import dextool.plugin.mutate.backend.analyze.schemata;
        import cpptooling.analyzer.clang.check_parse_result : hasParseErrors, logDiagnostic;

        logger.infof("Analyzing %s", checked_in_file);
        auto tu = ctx.makeTranslationUnit(checked_in_file, in_file.flags.completeFlags);
        if (tu.hasParseErrors) {
            logDiagnostic(tu);
            logger.error("Compile error...");
            return;
        }

        auto ast = toMutateAst(tu.cursor);
        debug logger.trace(ast);
        auto mutants = toMutants(ast, fio, val_loc);
        .destroy(ast);

        debug logger.trace(mutants);
        auto codeMutants = toCodeMutants(mutants, fio, tstream);
        debug logger.trace(codeMutants);
        () @trusted { .destroy(mutants); }();

        result.mutationPoints = codeMutants.points.byKeyValue.map!(
                a => a.value.map!(b => MutationPointEntry2(fio.toRelativeRoot(a.key),
                b.offset, b.sloc.begin, b.sloc.end, b.mutants))).joiner.array;
        foreach (f; codeMutants.points.byKey) {
            const id = result.idFile.length;
            result.idFile[f] = id;
            result.fileId[id] = f;
            result.infoId[id] = Result.FileInfo(codeMutants.csFiles[f], codeMutants.lang);
        }

        () @trusted { .destroy(codeMutants); }();
    }

    /**
     * Tokens are always from the same file.
     */
    void analyzeForComments(AbsolutePath file, TokenStream tstream) @trusted {
        import std.algorithm : filter;
        import clang.c.Index : CXTokenKind;
        import dextool.plugin.mutate.backend.database : LineMetadata, FileId, LineAttr, NoMut;

        const fid = result.idFile.require(file, result.fileId.length).FileId;

        auto mdata = appender!(LineMetadata[])();
        foreach (t; cache.getTokens(AbsolutePath(file), tstream)
                .filter!(a => a.kind == CXTokenKind.comment)) {
            auto m = matchFirst(t.spelling, re_nomut);
            if (m.whichPattern == 0)
                continue;

            mdata.put(LineMetadata(fid, t.loc.line, LineAttr(NoMut(m["tag"], m["comment"]))));
            logger.tracef("NOMUT found at %s:%s:%s", file, t.loc.line, t.loc.column);
        }

        result.metadata ~= mdata.data;
    }

    static class Result {
        import dextool.plugin.mutate.backend.type : Language;

        MutationPointEntry2[] mutationPoints;

        static struct FileInfo {
            Checksum checksum;
            Language language;
        }

        /// The key is the ID from idFile.
        FileInfo[ulong] infoId;

        /// The IDs is unique for *this* analyze, not globally.
        long[AbsolutePath] idFile;
        AbsolutePath[long] fileId;

        // The FileID used in the metadata is local to this analysis. It has to
        // be remapped when added to the database.
        LineMetadata[] metadata;
    }
}

@(
        "shall extract the tag and comment from the input following the pattern NOMUT with optional tag and comment")
unittest {
    import std.regex : regex, matchFirst;
    import unit_threaded.runner.io : writelnUt;

    auto re_nomut = regex(Analyze.raw_re_nomut);
    // NOMUT in other type of comments should NOT match.
    matchFirst("/// NOMUT", re_nomut).whichPattern.shouldEqual(0);
    matchFirst("// stuff with NOMUT in it", re_nomut).whichPattern.shouldEqual(0);
    matchFirst("/** NOMUT*/", re_nomut).whichPattern.shouldEqual(0);
    matchFirst("/* stuff with NOMUT in it */", re_nomut).whichPattern.shouldEqual(0);

    matchFirst("/*NOMUT*/", re_nomut).whichPattern.shouldEqual(1);
    matchFirst("/*NOMUT*/", re_nomut)["comment"].shouldEqual("");
    matchFirst("//NOMUT", re_nomut).whichPattern.shouldEqual(1);
    matchFirst("// NOMUT", re_nomut).whichPattern.shouldEqual(1);
    matchFirst("// NOMUT (arch)", re_nomut)["tag"].shouldEqual("arch");
    matchFirst("// NOMUT smurf", re_nomut)["comment"].shouldEqual("smurf");
    auto m = matchFirst("// NOMUT (arch) smurf", re_nomut);
    m["tag"].shouldEqual("arch");
    m["comment"].shouldEqual("smurf");
}

/// Stream of tokens excluding comment tokens.
class TokenStreamImpl : TokenStream {
    import std.typecons : NullableRef, nullableRef;
    import cpptooling.analyzer.clang.context : ClangContext;
    import dextool.plugin.mutate.backend.type : Token;

    NullableRef!ClangContext ctx;

    /// The context must outlive any instance of this class.
    this(ref ClangContext ctx) {
        this.ctx = nullableRef(&ctx);
    }

    Token[] getTokens(Path p) {
        import dextool.plugin.mutate.backend.utility : tokenize;

        return tokenize(ctx, p);
    }

    Token[] getFilteredTokens(Path p) {
        import std.array : array;
        import std.algorithm : filter;
        import clang.c.Index : CXTokenKind;
        import dextool.plugin.mutate.backend.utility : tokenize;

        // Filter a stream of tokens for those that should affect the checksum.
        return tokenize(ctx, p).filter!(a => a.kind != CXTokenKind.comment).array;
    }
}

/// Returns: true if `f` is inside any `roots`.
bool isPathInsideAnyRoot(AbsolutePath[] roots, AbsolutePath f) @safe {
    import dextool.utility : isPathInsideRoot;

    foreach (root; roots) {
        if (isPathInsideRoot(root, f))
            return true;
    }

    return false;
}

/** Update the connection between the marked mutants and their mutation status
 * id and mutation id.
 */
void updateMarkedMutants(ref Database db) {
    import dextool.plugin.mutate.backend.database.type : MutationStatusId;

    void update(MarkedMutant m) {
        const stId = db.getMutationStatusId(m.statusChecksum);
        if (stId.isNull)
            return;
        const mutId = db.getMutationId(stId.get);
        if (mutId.isNull)
            return;
        db.removeMarkedMutant(m.statusChecksum);
        db.markMutant(mutId.get, m.path, m.sloc, stId.get, m.statusChecksum,
                m.toStatus, m.rationale, m.mutText);
        db.updateMutationStatus(stId.get, m.toStatus);
    }

    // find those marked mutants that have a checksum that is different from
    // the mutation status the marked mutant is related to. If possible change
    // the relation to the correct mutation status id.
    foreach (m; db.getMarkedMutants
            .map!(a => tuple(a, db.getChecksum(a.statusId)))
            .filter!(a => !a[1].isNull)
            .filter!(a => a[0].statusChecksum != a[1].get)) {
        update(m[0]);
    }
}

/// Prints a marked mutant that has become lost due to rerun of analyze
void printLostMarkings(MarkedMutant[] lostMutants) {
    import std.algorithm : sort;
    import std.array : empty;
    import std.conv : to;
    import std.stdio : writeln;

    if (lostMutants.empty)
        return;

    Table!6 tbl = Table!6([
            "ID", "File", "Line", "Column", "Status", "Rationale"
            ]);
    foreach (m; lostMutants) {
        typeof(tbl).Row r = [
            m.mutationId.to!string, m.path, m.sloc.line.to!string,
            m.sloc.column.to!string, m.toStatus.to!string, m.rationale
        ];
        tbl.put(r);
    }
    logger.warning("Marked mutants was lost");
    writeln(tbl);
}

@("shall only let files in the diff through")
unittest {
    import std.string : lineSplitter;
    import dextool.plugin.mutate.backend.diff_parser;

    immutable lines = `diff --git a/standalone2.d b/standalone2.d
index 0123..2345 100644
--- a/standalone.d
+++ b/standalone2.d
@@ -31,7 +31,6 @@ import std.algorithm : map;
 import std.array : Appender, appender, array;
 import std.datetime : SysTime;
+import std.format : format;
-import std.typecons : Tuple;

 import d2sqlite3 : sqlDatabase = Database;

@@ -46,7 +45,7 @@ import dextool.plugin.mutate.backend.type : Language;
 struct Database {
     import std.conv : to;
     import std.exception : collectException;
-    import std.typecons : Nullable;
+    import std.typecons : Nullable, Flag, No;
     import dextool.plugin.mutate.backend.type : MutationPoint, Mutation, Checksum;

+    sqlDatabase db;`;

    UnifiedDiffParser p;
    foreach (line; lines.lineSplitter)
        p.process(line);
    auto diff = p.result;

    auto files = FileFilter(".".Path.AbsolutePath, true, diff);

    files.shouldAnalyze("standalone.d".Path.AbsolutePath).shouldBeFalse;
    files.shouldAnalyze("standalone2.d".Path.AbsolutePath).shouldBeTrue;
}
