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
import std.array : array, appender, empty;
import std.concurrency;
import std.datetime : dur;
import std.exception : collectException;
import std.parallelism;
import std.range : tee, enumerate;
import std.typecons;

import colorlog;
import my.set;

import dextool.compilation_db : CompileCommandFilter, defaultCompilerFlagFilter,
    CompileCommandDB, ParsedCompileCommandRange, ParsedCompileCommand;
import dextool.plugin.mutate.backend.analyze.internal : Cache, TokenStream;
import dextool.plugin.mutate.backend.database : Database, LineMetadata, MutationPointEntry2;
import dextool.plugin.mutate.backend.database.type : MarkedMutant;
import dextool.plugin.mutate.backend.diff_parser : Diff;
import dextool.plugin.mutate.backend.interface_ : ValidateLoc, FilesysIO;
import dextool.plugin.mutate.backend.report.utility : statusToString, Table;
import dextool.plugin.mutate.backend.utility : checksum, trustedRelativePath,
    Checksum, getProfileResult, Profile;
import dextool.plugin.mutate.config : ConfigCompiler, ConfigAnalyze;
import dextool.type : ExitStatusType, AbsolutePath, Path;

version (unittest) {
    import unit_threaded.assertions;
}

/** Analyze the files in `frange` for mutations.
 */
ExitStatusType runAnalyzer(ref Database db, ConfigAnalyze conf_analyze, ConfigCompiler conf_compiler,
        ParsedCompileCommandRange frange, ValidateLoc val_loc, FilesysIO fio) @trusted {
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
            conf_analyze.prune, conf_analyze.fastDbStore,
            conf_analyze.poolSize, conf_analyze.forceSaveAnalyze);

    int taskCnt;
    Set!AbsolutePath alreadyAnalyzed;
    // dfmt off
    foreach (f; frange
            // The tool only supports analyzing a file one time.
            // This optimize it in some cases where the same file occurs
            // multiple times in the compile commands database.
            .filter!(a => a.cmd.absoluteFile !in alreadyAnalyzed)
            .tee!(a => alreadyAnalyzed.add(a.cmd.absoluteFile))
            .cache
            .filter!(a => !isPathInsideAnyRoot(conf_analyze.exclude, a.cmd.absoluteFile))
            .filter!(a => fileFilter.shouldAnalyze(a.cmd.absoluteFile))) {
        try {
            pool.put(task!analyzeActor(f, val_loc.dup, fio.dup, conf_compiler, conf_analyze, store));
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
void analyzeActor(ParsedCompileCommand fileToAnalyze, ValidateLoc vloc, FilesysIO fio,
        ConfigCompiler compilerConf, ConfigAnalyze analyzeConf, Tid storeActor) @trusted nothrow {
    auto profile = Profile("analyze file " ~ fileToAnalyze.cmd.absoluteFile);

    try {
        auto analyzer = Analyze(vloc, fio,
                Analyze.Config(compilerConf.forceSystemIncludes, analyzeConf.mutantsPerSchema));
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
        const bool prune, const bool fastDbStore, const long poolSize, const bool forceSave) @trusted nothrow {
    import cachetools : CacheLRU;
    import dextool.cachetools : nullableCache;
    import dextool.plugin.mutate.backend.database : LineMetadata, FileId, LineAttr, NoMut;

    Database* db = cast(Database*) dbShared;
    FilesysIO fio = cast(FilesysIO) fioShared;

    // A file is at most saved one time to the database.
    Set!AbsolutePath savedFiles;

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
                .filter!(a => getFileDbChecksum(fio.toRelativeRoot(a)) == getFileFsChecksum(a)
                    && !forceSave)) {
            logger.info("Unchanged ".color(Color.yellow), f);
            savedFiles.add(f);
        }

        // only saves mutation points to a file one time.
        {
            auto app = appender!(MutationPointEntry2[])();
            bool isChanged;
            foreach (mp; result.mutationPoints
                    .map!(a => tuple!("data", "file")(a, fio.toAbsoluteRoot(a.file)))
                    .filter!(a => a.file !in savedFiles)) {
                app.put(mp.data);
            }
            foreach (f; result.idFile.byKey.filter!(a => a !in savedFiles)) {
                isChanged = true;
                logger.info("Saving ".color(Color.green), f);
                const relp = fio.toRelativeRoot(f);
                db.removeFile(relp);
                const info = result.infoId[result.idFile[f]];
                db.put(relp, info.checksum, info.language);
                savedFiles.add(f);
            }
            db.put(app.data, fio.getOutputDir);

            // only save the schematas if mutation points where saved.  this
            // ensure that only schematas for changed/new files are saved.
            if (isChanged) {
                foreach (s; result.schematas.enumerate) {
                    try {
                        auto mutants = result.schemataMutants[s.index].map!(
                                a => db.getMutationStatusId(a.value))
                            .filter!(a => !a.isNull)
                            .map!(a => a.get)
                            .array;
                        if (!mutants.empty && !s.value.empty) {
                            const id = db.putSchemata(result.schemataChecksum[s.index],
                                    s.value, mutants);
                            logger.trace(!id.isNull, "Saving schemata ", id.get);
                        }
                    } catch (Exception e) {
                        logger.trace(e.msg);
                        logger.warning("Unable to save schemata ", s.index).collectException;
                    }
                }
            }
        }

        {
            Set!long printed;
            auto app = appender!(LineMetadata[])();
            foreach (md; result.metadata) {
                // transform the ID from local to global.
                const fid = getFileId(fio.toRelativeRoot(result.fileId[md.id.get]));
                if (fid.isNull && !printed.contains(md.id.get)) {
                    printed.add(md.id.get);
                    logger.warningf("File with suppressed mutants (// NOMUT) not in the database: %s. Skipping...",
                            result.fileId[md.id.get]).collectException;
                } else if (!fid.isNull) {
                    app.put(LineMetadata(fid.get, md.line, md.attr));
                }
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
        auto files = db.getFiles.map!(a => fio.toAbsoluteRoot(a)).toSet;

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
            {
                auto profile = Profile("remove orphaned mutants");
                logger.info("Removing orphaned mutants");
                db.removeOrphanedMutants;
            }
            {
                auto profile = Profile("prune schematas");
                logger.info("Prune schematas");
                db.pruneSchemas;
            }
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
        logger.error("Failed to save the result of the analyze to the database").collectException;
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
    import std.typecons : Yes;
    import cpptooling.analyzer.clang.context : ClangContext;
    import cpptooling.utility.virtualfilesystem;
    import dextool.type : Exists, makeExists;

    static struct Config {
        bool forceSystemIncludes;
        long mutantsPerSchema;
    }

    private {
        static immutable raw_re_nomut = `^((//)|(/\*))\s*NOMUT\s*(\((?P<tag>.*)\))?\s*((?P<comment>.*)\*/|(?P<comment>.*))?`;

        Regex!char re_nomut;

        ValidateLoc val_loc;
        FilesysIO fio;
        bool forceSystemIncludes;

        Cache cache;

        Result result;

        Config conf;
    }

    this(ValidateLoc val_loc, FilesysIO fio, Config conf) @trusted {
        this.val_loc = val_loc;
        this.fio = fio;
        this.cache = new Cache;
        this.re_nomut = regex(raw_re_nomut);
        this.forceSystemIncludes = forceSystemIncludes;
        this.result = new Result;
        this.conf = conf;
    }

    void process(ParsedCompileCommand in_file) @safe {
        in_file.flags.forceSystemIncludes = conf.forceSystemIncludes;

        // find the file and flags to analyze
        Exists!AbsolutePath checked_in_file;
        try {
            checked_in_file = makeExists(in_file.cmd.absoluteFile);
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
            logger.error("failed analyze of ", in_file.cmd.absoluteFile).collectException;
        }
    }

    void analyzeForMutants(ParsedCompileCommand in_file,
            Exists!AbsolutePath checked_in_file, ref ClangContext ctx, TokenStream tstream) @safe {
        import dextool.plugin.mutate.backend.analyze.pass_clang;
        import dextool.plugin.mutate.backend.analyze.pass_filter;
        import dextool.plugin.mutate.backend.analyze.pass_mutant;
        import dextool.plugin.mutate.backend.analyze.pass_schemata;
        import cpptooling.analyzer.clang.check_parse_result : hasParseErrors, logDiagnostic;

        logger.infof("Analyzing %s", checked_in_file);
        auto tu = ctx.makeTranslationUnit(checked_in_file, in_file.flags.completeFlags);
        if (tu.hasParseErrors) {
            logDiagnostic(tu);
            logger.errorf("Compile error in %s. Skipping", checked_in_file);
            return;
        }

        auto ast = toMutateAst(tu.cursor, fio);
        debug logger.trace(ast);

        auto codeMutants = () {
            auto mutants = toMutants(ast, fio, val_loc);
            debug logger.trace(mutants);

            debug logger.trace("filter mutants");
            mutants = filterMutants(fio, mutants);
            debug logger.trace(mutants);

            return toCodeMutants(mutants, fio, tstream);
        }();
        debug logger.trace(codeMutants);

        {
            auto schemas = toSchemata(ast, fio, codeMutants, conf.mutantsPerSchema);
            ast.release;

            debug logger.trace(schemas);
            foreach (f; schemas.getSchematas.filter!(a => !(a.fragments.empty || a.mutants.empty))) {
                const id = result.schematas.length;
                result.schematas ~= f.fragments;
                result.schemataMutants[id] = f.mutants.map!(a => a.id).array;
                result.schemataChecksum[id] = f.checksum;
            }
        }

        result.mutationPoints = codeMutants.points.byKeyValue.map!(
                a => a.value.map!(b => MutationPointEntry2(fio.toRelativeRoot(a.key),
                b.offset, b.sloc.begin, b.sloc.end, b.mutants))).joiner.array;
        foreach (f; codeMutants.points.byKey) {
            const id = result.idFile.length;
            result.idFile[f] = id;
            result.fileId[id] = f;
            result.infoId[id] = Result.FileInfo(codeMutants.csFiles[f], codeMutants.lang);
        }
    }

    /** Tokens are always from the same file.
     *
     * TODO: move this to pass_clang.
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
        import dextool.plugin.mutate.backend.type : Language, CodeChecksum, SchemataChecksum;
        import dextool.plugin.mutate.backend.database.type : SchemataFragment;

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

        /// Mutant schematas that has been generated.
        SchemataFragment[][] schematas;
        /// the mutants that are associated with a schemata.
        CodeChecksum[][long] schemataMutants;
        /// checksum for the schemata
        SchemataChecksum[long] schemataChecksum;
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
    import cpptooling.analyzer.clang.context : ClangContext;
    import dextool.plugin.mutate.backend.type : Token;
    import dextool.plugin.mutate.backend.utility : tokenize;

    ClangContext* ctx;

    /// The context must outlive any instance of this class.
    // TODO remove @trusted when upgrading to dmd-fe 2.091.0+ and activate dip25 + 1000
    this(ref ClangContext ctx) @trusted {
        this.ctx = &ctx;
    }

    Token[] getTokens(Path p) {
        return tokenize(*ctx, p);
    }

    Token[] getFilteredTokens(Path p) {
        import clang.c.Index : CXTokenKind;

        // Filter a stream of tokens for those that should affect the checksum.
        return tokenize(*ctx, p).filter!(a => a.kind != CXTokenKind.comment).array;
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
            m.mutationId.get.to!string, m.path, m.sloc.line.to!string,
            m.sloc.column.to!string, m.toStatus.to!string, m.rationale.get
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
