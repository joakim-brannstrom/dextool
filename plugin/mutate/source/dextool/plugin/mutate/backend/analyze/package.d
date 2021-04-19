/**cpptooling.analyzer.clang
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
import std.datetime : dur, Duration;
import std.exception : collectException;
import std.parallelism;
import std.range : tee, enumerate;
import std.typecons : tuple;

import colorlog;
import my.filter : GlobFilter;
import my.named_type;
import my.optional;
import my.set;

import dextool.utility : dextoolBinaryId;

import dextool.compilation_db : CompileCommandFilter, defaultCompilerFlagFilter, CompileCommandDB,
    ParsedCompileCommandRange, ParsedCompileCommand, ParseFlags, SystemIncludePath;
import dextool.plugin.mutate.backend.analyze.internal : Cache, TokenStream;
import dextool.plugin.mutate.backend.analyze.pass_schemata : SchemataResult;
import dextool.plugin.mutate.backend.database : Database, LineMetadata,
    MutationPointEntry2, DepFile;
import dextool.plugin.mutate.backend.database.type : MarkedMutant, TestFile,
    TestFilePath, TestFileChecksum, ToolVersion;
import dextool.plugin.mutate.backend.diff_parser : Diff;
import dextool.plugin.mutate.backend.interface_ : ValidateLoc, FilesysIO;
import dextool.plugin.mutate.backend.report.utility : statusToString, Table;
import dextool.plugin.mutate.backend.utility : checksum, Checksum, getProfileResult, Profile;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.type : MutationKind;
import dextool.plugin.mutate.config : ConfigCompiler, ConfigAnalyze;
import dextool.type : ExitStatusType, AbsolutePath, Path;

version (unittest) {
    import unit_threaded.assertions;
}

/** Analyze the files in `frange` for mutations.
 */
ExitStatusType runAnalyzer(const AbsolutePath dbPath, const MutationKind[] userKinds, ConfigAnalyze confAnalyze,
        ConfigCompiler conf_compiler, ParsedCompileCommandRange frange,
        ValidateLoc valLoc, FilesysIO fio) @trusted {
    import dextool.plugin.mutate.backend.diff_parser : diffFromStdin, Diff;
    import dextool.plugin.mutate.backend.mutation_type : toInternal;

    auto fileFilter = () {
        try {
            return FileFilter(fio.getOutputDir, confAnalyze.unifiedDiffFromStdin,
                    confAnalyze.unifiedDiffFromStdin ? diffFromStdin : Diff.init);
        } catch (Exception e) {
            logger.info(e.msg);
            logger.warning("Unable to parse diff");
        }
        return FileFilter.init;
    }();

    bool shouldAnalyze(AbsolutePath p) {
        return confAnalyze.fileMatcher.match(p.toString) && fileFilter.shouldAnalyze(p);
    }

    auto pool = () {
        if (confAnalyze.poolSize == 0)
            return new TaskPool();
        return new TaskPool(confAnalyze.poolSize);
    }();

    // if a dependency of a root file has been changed.
    auto changedDeps = dependencyAnalyze(dbPath, fio);

    // will only be used by one thread at a time.
    auto store = spawn(&storeActor, dbPath, cast(shared) fio.dup,
            cast(shared) confAnalyze, cast(immutable) changedDeps.byKeyValue
            .filter!(a => !a.value)
            .map!(a => a.key)
            .array);

    try {
        pool.put(task!testPathActor(confAnalyze.testPaths,
                confAnalyze.testFileMatcher, fio.dup, store));
    } catch (Exception e) {
        logger.trace(e);
        logger.warning(e.msg);
    }

    auto kinds = toInternal(userKinds);
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
            .filter!(a => shouldAnalyze(a.cmd.absoluteFile))
            ) {
        try {
            if (auto v = fio.toRelativeRoot(f.cmd.absoluteFile) in changedDeps) {
                if (!(*v || confAnalyze.forceSaveAnalyze))
                    continue;
            }

            //logger.infof("%s sending", f.cmd.absoluteFile);
            pool.put(task!analyzeActor(kinds, f, valLoc.dup, fio.dup, conf_compiler, confAnalyze, store));
            taskCnt++;
        } catch (Exception e) {
            logger.trace(e);
            logger.warning(e.msg);
        }
    }
    // dfmt on

    changedDeps = typeof(changedDeps).init; // free the memory

    // inform the store actor of how many analyse results it should *try* to
    // save.
    send(store, AnalyzeCntMsg(taskCnt));
    // wait for all files to be analyzed
    pool.finish(true);
    // wait for the store actor to finish
    receiveOnly!StoreDoneMsg;

    if (confAnalyze.profile)
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
 *
 * TODO: this may create problems for header only libraries because only the
 * unittest would include the header which mean that for this to work the
 * unittest would have to reside in the same directory as the header file.
 * Which they normally never do. This then lead to a diff of a header only lib
 * lead to "no files analyzed".
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

/// The main thread is waiting for storeActor to send this message.
struct StoreDoneMsg {
}

/// Start an analyze of a file
void analyzeActor(Mutation.Kind[] kinds, ParsedCompileCommand fileToAnalyze, ValidateLoc vloc,
        FilesysIO fio, ConfigCompiler compilerConf, ConfigAnalyze analyzeConf, Tid storeActor) @trusted nothrow {
    auto profile = Profile("analyze file " ~ fileToAnalyze.cmd.absoluteFile);

    try {
        //logger.infof("%s begin", fileToAnalyze.cmd.absoluteFile);
        auto analyzer = Analyze(kinds, vloc, fio, Analyze.Config(compilerConf.forceSystemIncludes,
                analyzeConf.saveCoverage.get, compilerConf.allowErrors.get));
        analyzer.process(fileToAnalyze);
        send(storeActor, cast(immutable) analyzer.result);
        //logger.infof("%s end", fileToAnalyze.cmd.absoluteFile);
        return;
    } catch (Exception e) {
        logger.error(e.msg).collectException;
    }

    // send a dummy result
    try {
        //logger.infof("%s failed", fileToAnalyze.cmd.absoluteFile);
        send(storeActor, cast(immutable) new Analyze.Result);
    } catch (Exception e) {
        logger.error(e.msg).collectException;
    }
}

class TestFileResult {
    Duration time;
    TestFile[Checksum] files;
}

void testPathActor(const AbsolutePath[] userPaths, GlobFilter matcher, FilesysIO fio, Tid storeActor) @trusted nothrow {
    import std.datetime : Clock;
    import std.datetime.stopwatch : StopWatch, AutoStart;
    import std.file : isDir, isFile, dirEntries, SpanMode;
    import my.container.vector;

    auto profile = Profile("checksum test files");

    auto sw = StopWatch(AutoStart.yes);

    TestFile makeTestFile(const AbsolutePath file) {
        auto cs = checksum(fio.makeInput(file).content[]);
        return TestFile(TestFilePath(fio.toRelativeRoot(file)),
                TestFileChecksum(cs), Clock.currTime);
    }

    auto paths = vector(userPaths.dup);

    auto tfiles = new TestFileResult;
    scope (exit)
        tfiles.time = sw.peek;

    while (!paths.empty) {
        try {
            if (isDir(paths.front)) {
                logger.trace("  Test directory ", paths.front);
                foreach (a; dirEntries(paths.front, SpanMode.shallow).map!(
                        a => AbsolutePath(a.name))) {
                    paths.put(a);
                }
            } else if (isFile(paths.front) && matcher.match(paths.front)) {
                logger.trace("  Test saved ", paths.front);
                auto t = makeTestFile(paths.front);
                tfiles.files[t.checksum.get] = t;
            }
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }

        paths.popFront;
    }

    logger.infof("Found %s test files", tfiles.files.length).collectException;

    try {
        send(storeActor, cast(immutable) tfiles);
    } catch (Exception e) {
    }
}

/// Store the result of the analyze.
void storeActor(const AbsolutePath dbPath, scope shared FilesysIO fioShared,
        scope shared ConfigAnalyze confAnalyzeShared, immutable Path[] rootFiles) @trusted nothrow {
    import cachetools : CacheLRU;
    import dextool.cachetools : nullableCache;
    import dextool.plugin.mutate.backend.database : LineMetadata, FileId, LineAttr, NoMut;

    const confAnalyze = cast() confAnalyzeShared;

    // The conditions that the storeActor is waiting for receiving the results
    // from the workers.
    static struct RecvWaiter {
        int analyzeFileWaitCnt = int.max;
        int analyzeFileCnt;

        bool isTestFilesDone;

        bool isWaiting() {
            return analyzeFileCnt < analyzeFileWaitCnt || !isTestFilesDone;
        }
    }

    static struct SchemataSaver {
        import sumtype;
        import my.optional;
        import dextool.plugin.mutate.backend.analyze.pass_schemata : SchemataBuilder;

        typeof(ConfigAnalyze.minMutantsPerSchema) minMutantsPerSchema;
        typeof(ConfigAnalyze.mutantsPerSchema) mutantsPerSchema;
        SchemataBuilder builder;

        void put(FilesysIO fio, SchemataResult.Schemata[AbsolutePath] a) {
            builder.put(fio, a);
        }

        void process(ref Database db, Optional!(SchemataBuilder.ET) value) {
            value.match!((Some!(SchemataBuilder.ET) a) {
                try {
                    auto mutants = a.mutants
                        .map!(a => db.getMutationStatusId(a.id))
                        .filter!(a => !a.isNull)
                        .map!(a => a.get)
                        .array;
                    if (!mutants.empty) {
                        const id = db.putSchemata(a.checksum, a.fragments, mutants);
                        logger.tracef(!id.isNull, "Saving schema %s with %s mutants",
                            id.get.get, mutants.length);
                    }
                } catch (Exception e) {
                    logger.trace(e.msg);
                }
            }, (None a) {});
        }

        /// Consume fragments used by scheman containing >min mutants.
        void intermediate(ref Database db) {
            builder.discardMinScheman = false;
            builder.mutantsPerSchema = mutantsPerSchema.get;
            builder.minMutantsPerSchema = mutantsPerSchema.get;

            while (!builder.isDone) {
                process(db, builder.next);
            }

            builder.restart;
        }

        /// Consume all fragments or discard.
        void finalize(ref Database db) {
            builder.discardMinScheman = true;
            builder.mutantsPerSchema = mutantsPerSchema.get;
            builder.minMutantsPerSchema = minMutantsPerSchema.get;

            // two loops to pass over all mutants and retry new schema
            // compositions. Any schema that is less than the minimum will be
            // discarded so the number of mutants will shrink.
            while (!builder.isDone) {
                while (!builder.isDone) {
                    process(db, builder.next);
                }
                builder.restart;
            }
        }
    }

    auto schemas = SchemataSaver(confAnalyze.minMutantsPerSchema, confAnalyze.mutantsPerSchema);

    void helper(FilesysIO fio, ref Database db) nothrow {
        // A file is at most saved one time to the database.
        Set!AbsolutePath savedFiles;

        const isToolVersionDifferent = () nothrow{
            try {
                return db.isToolVersionDifferent(ToolVersion(dextoolBinaryId));
            } catch (Exception e) {
            }
            return true;
        }();

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

        void save(immutable Analyze.Result result_) {
            import dextool.plugin.mutate.backend.type : Language;

            auto result = cast() result_;

            auto profile = Profile("save " ~ result.root);

            // mark files that have an unchanged checksum as "already saved"
            foreach (f; result.idFile
                    .byKey
                    .filter!(a => a !in savedFiles)
                    .filter!(a => getFileDbChecksum(fio.toRelativeRoot(a)) == getFileFsChecksum(a)
                        && !confAnalyze.forceSaveAnalyze && !isToolVersionDifferent)) {
                logger.info("Unchanged ".color(Color.yellow), f);
                savedFiles.add(f);
            }

            // only saves mutation points to a file one time.
            {
                auto app = appender!(MutationPointEntry2[])();
                bool isChanged = isToolVersionDifferent;
                foreach (mp; result.mutationPoints
                        .map!(a => tuple!("data", "file")(a, fio.toAbsoluteRoot(a.file)))
                        .filter!(a => a.file !in savedFiles)) {
                    app.put(mp.data);
                }
                foreach (f; result.idFile.byKey.filter!(a => a !in savedFiles)) {
                    isChanged = true;
                    logger.info("Saving ".color(Color.green), f);
                    const relp = fio.toRelativeRoot(f);

                    // this is critical in order to remove old data about a file.
                    db.removeFile(relp);

                    const info = result.infoId[result.idFile[f]];
                    db.put(relp, info.checksum, info.language, f == result.root);
                    savedFiles.add(f);
                }
                db.put(app.data, fio.getOutputDir);

                if (result.root !in savedFiles) {
                    // this occurs when the file is e.g. a unittest that uses a
                    // header only library. The unittests are not mutated thus
                    // no mutation points exists in them but we want dextool to
                    // still, if possible, track the unittests for changes.
                    isChanged = true;
                    const relp = fio.toRelativeRoot(result.root);
                    db.removeFile(relp);
                    // the language do not matter because it is a file without
                    // any mutants.
                    db.put(relp, result.rootCs, Language.init, true);
                    savedFiles.add(fio.toAbsoluteRoot(result.root));
                }

                // must always update dependencies because they may not contain
                // mutants. Only files that are changed and contain mutants
                // trigger isChanged to be true.
                db.dependencyApi.set(fio.toRelativeRoot(result.root), result.dependencies);

                if (isChanged) {
                    foreach (a; result.coverage.byKeyValue) {
                        const fid = getFileId(fio.toRelativeRoot(result.fileId[a.key]));
                        if (!fid.isNull) {
                            db.clearCoverageMap(fid.get);
                            db.putCoverageMap(fid.get, a.value);
                        }
                    }

                    // only save the schematas if mutation points where saved.
                    // This ensure that only schematas for changed/new files
                    // are saved.
                    schemas.put(fio, result.schematas);
                    schemas.intermediate(db);
                }
            }

            {
                Set!long printed;
                auto app = appender!(LineMetadata[])();
                foreach (md; result.metadata) {
                    const localId = Analyze.Result.LocalFileId(md.id.get);
                    // transform the ID from local to global.
                    const fid = getFileId(fio.toRelativeRoot(result.fileId[localId]));
                    if (fid.isNull && !printed.contains(md.id.get)) {
                        printed.add(md.id.get);
                        logger.info("File with suppressed mutants (// NOMUT) not in the database: ",
                                result.fileId[localId]).collectException;
                    } else if (!fid.isNull) {
                        app.put(LineMetadata(fid.get, md.line, md.attr));
                    }
                }
                db.put(app.data);
            }
        }

        void saveTestResult(immutable TestFileResult result) {
            auto profile = Profile("save test files");
            Set!Checksum old;

            foreach (a; db.getTestFiles) {
                old.add(a.checksum.get);
                if (a.checksum.get !in result.files) {
                    logger.info("Removed test file ", a.file.get.toString);
                    db.removeFile(a.file);
                }
            }

            foreach (a; result.files.byValue.filter!(a => a.checksum.get !in old)) {
                logger.info("Saving test file ", a.file.get.toString);
                db.put(a);
            }
        }

        // listen for results from workers until the expected number is processed.
        void recv() {
            logger.info("Updating files");
            RecvWaiter waiter;

            while (waiter.isWaiting) {
                try {
                    receive((AnalyzeCntMsg a) {
                        waiter.analyzeFileWaitCnt = a.value;
                    }, (immutable Analyze.Result a) {
                        auto trans = db.transaction;
                        waiter.analyzeFileCnt++;
                        save(a);
                        trans.commit;

                        logger.infof("Analyzed file %s/%s",
                            waiter.analyzeFileCnt, waiter.analyzeFileWaitCnt);
                    }, (immutable TestFileResult a) {
                        auto trans = db.transaction;
                        waiter.isTestFilesDone = true;
                        saveTestResult(a);
                        trans.commit;

                        logger.info("Done analyzing test files in ", a.time);
                    });
                } catch (Exception e) {
                    logger.trace(e).collectException;
                    logger.warning(e.msg).collectException;
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

        void addRoots() {
            if (confAnalyze.forceSaveAnalyze || isToolVersionDifferent)
                return;

            // add root files and their dependencies that has not been analyzed because nothing has changed.
            // By adding them they are not removed.

            auto profile = Profile("add roots and dependencies");
            foreach (a; rootFiles) {
                auto p = fio.toAbsoluteRoot(a);
                if (p !in savedFiles) {
                    savedFiles.add(p);
                    // fejk text for the user to tell them that yes, the files have
                    // been analyzed.
                    logger.info("Analyzing ", a);
                    logger.info("Unchanged ".color(Color.yellow), a);
                }
            }
            foreach (a; rootFiles.map!(a => db.dependencyApi.get(a)).joiner) {
                savedFiles.add(fio.toAbsoluteRoot(a));
            }
        }

        void fastDbOn() {
            if (!confAnalyze.fastDbStore)
                return;
            logger.info(
                    "Turning OFF sqlite3 synchronization protection to improve the write performance");
            logger.warning(
                    "Do NOT interrupt dextool in any way because it may corrupt the database");
            db.run("PRAGMA synchronous = OFF");
            db.run("PRAGMA journal_mode = MEMORY");
        }

        void fastDbOff() {
            if (!confAnalyze.fastDbStore)
                return;
            db.run("PRAGMA synchronous = ON");
            db.run("PRAGMA journal_mode = DELETE");
        }

        try {
            import dextool.plugin.mutate.backend.test_mutant.timeout : resetTimeoutContext;

            // by making the mailbox size follow the number of workers the overall
            // behavior will slow down if saving to the database is too slow. This
            // avoids excessive or even fatal memory usage.
            setMaxMailboxSize(thisTid, confAnalyze.poolSize + 2, OnCrowding.block);

            fastDbOn();

            {
                auto trans = db.transaction;
                auto profile = Profile("prune old schemas");
                logger.info("Prune database of schemata created by an old version");
                if (db.pruneOldSchemas(ToolVersion(dextoolBinaryId)).get)
                    logger.info("Done".color.fggreen);
                trans.commit;
            }

            recv();
            {
                auto trans = db.transaction;
                schemas.finalize(db);
                trans.commit;
            }

            {
                auto trans = db.transaction;
                addRoots();

                logger.info("Resetting timeout context");
                resetTimeoutContext(db);

                logger.info("Updating metadata");
                db.updateMetadata;

                if (confAnalyze.prune) {
                    pruneFiles();
                    {
                        auto profile = Profile("remove orphaned mutants");
                        logger.info("Removing orphaned mutants");
                        db.removeOrphanedMutants;
                    }
                    {
                        auto profile = Profile("prune schemas");
                        logger.info("Prune the database of unused schemas");
                        db.pruneSchemas;
                    }
                    {
                        auto profile = Profile("prune dependencies");
                        logger.info("Prune dependencies");
                        db.dependencyApi.cleanup;
                    }
                }

                logger.info("Updating manually marked mutants");
                updateMarkedMutants(db);
                printLostMarkings(db.getLostMarkings);

                logger.info("Updating tool version");
                db.updateToolVersion(ToolVersion(dextoolBinaryId));

                logger.info("Committing changes");
                trans.commit;
                logger.info("Ok".color(Color.green));
            }

            fastDbOff();

            if (isToolVersionDifferent) {
                auto profile = Profile("compact");
                logger.info("Compacting the database");
                db.vacuum;
            }
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            logger.error("Failed to save the result of the analyze to the database")
                .collectException;
        }

        try {
            send(ownerTid, StoreDoneMsg.init);
        } catch (Exception e) {
            logger.errorf("Fatal error. Unable to send %s to the main thread",
                    StoreDoneMsg.init).collectException;
        }
    }

    try {
        FilesysIO fio = cast(FilesysIO) fioShared;
        auto db = Database.make(dbPath);
        helper(fio, db);
    } catch (Exception e) {
        logger.error(e.msg).collectException;
    }
}

/// Analyze a file for mutants.
struct Analyze {
    import std.regex : Regex, regex, matchFirst;
    import std.typecons : Yes;
    import libclang_ast.context : ClangContext;

    static struct Config {
        bool forceSystemIncludes;
        bool saveCoverage;
        bool allowErrors;
    }

    private {
        static immutable rawReNomut = `^((//)|(/\*))\s*NOMUT\s*(\((?P<tag>.*)\))?\s*((?P<comment>.*)\*/|(?P<comment>.*))?`;

        Regex!char re_nomut;

        ValidateLoc valLoc;
        FilesysIO fio;

        Cache cache;

        Result result;

        Config conf;

        Mutation.Kind[] kinds;
    }

    this(Mutation.Kind[] kinds, ValidateLoc valLoc, FilesysIO fio, Config conf) @trusted {
        this.kinds = kinds;
        this.valLoc = valLoc;
        this.fio = fio;
        this.cache = new Cache;
        this.re_nomut = regex(rawReNomut);
        this.result = new Result;
        this.conf = conf;
    }

    void process(ParsedCompileCommand commandsForFileToAnalyze) @safe {
        import std.file : exists;

        commandsForFileToAnalyze.flags.forceSystemIncludes = conf.forceSystemIncludes;

        try {
            if (!exists(commandsForFileToAnalyze.cmd.absoluteFile)) {
                logger.warningf("Failed to analyze %s. Do not exist",
                        commandsForFileToAnalyze.cmd.absoluteFile);
                return;
            }
        } catch (Exception e) {
            logger.warning(e.msg);
            return;
        }

        result.root = commandsForFileToAnalyze.cmd.absoluteFile;

        try {
            result.rootCs = checksum(result.root);

            auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
            auto tstream = new TokenStreamImpl(ctx);

            analyzeForMutants(commandsForFileToAnalyze, result.root, ctx, tstream);
            foreach (f; result.fileId.byValue)
                analyzeForComments(f, tstream);
        } catch (Exception e) {
            () @trusted { logger.trace(e); }();
            logger.info(e.msg);
            logger.error("failed analyze of ",
                    commandsForFileToAnalyze.cmd.absoluteFile).collectException;
        }
    }

    void analyzeForMutants(ParsedCompileCommand commandsForFileToAnalyze,
            AbsolutePath fileToAnalyze, ref ClangContext ctx, TokenStream tstream) @safe {
        import my.gc.refc : RefCounted;
        import dextool.plugin.mutate.backend.analyze.ast : Ast;
        import dextool.plugin.mutate.backend.analyze.pass_clang;
        import dextool.plugin.mutate.backend.analyze.pass_coverage;
        import dextool.plugin.mutate.backend.analyze.pass_filter;
        import dextool.plugin.mutate.backend.analyze.pass_mutant;
        import dextool.plugin.mutate.backend.analyze.pass_schemata;
        import libclang_ast.check_parse_result : hasParseErrors, logDiagnostic;

        logger.info("Analyzing ", fileToAnalyze);
        RefCounted!(Ast) ast;
        {
            auto tu = ctx.makeTranslationUnit(fileToAnalyze,
                    commandsForFileToAnalyze.flags.completeFlags);
            if (tu.hasParseErrors) {
                logDiagnostic(tu);
                logger.warningf("Compile error in %s", fileToAnalyze);
                if (!conf.allowErrors) {
                    logger.warning("Skipping");
                    return;
                }
            }

            auto res = toMutateAst(tu.cursor, fio);
            ast = res.ast;
            saveDependencies(commandsForFileToAnalyze.flags, result.root, res.dependencies);
            debug logger.trace(ast);
        }

        auto codeMutants = () {
            auto mutants = toMutants(ast, fio, valLoc, kinds);
            debug logger.trace(mutants);

            debug logger.trace("filter mutants");
            mutants = filterMutants(fio, mutants);
            debug logger.trace(mutants);

            return toCodeMutants(mutants, fio, tstream);
        }();
        debug logger.trace(codeMutants);

        {
            auto schemas = toSchemata(ast, fio, codeMutants);
            debug logger.trace(schemas);
            logger.tracef("path dedup count:%s length_acc:%s", ast.paths.count,
                    ast.paths.lengthAccum);

            result.schematas = schemas.getSchematas;
        }

        result.mutationPoints = codeMutants.points.byKeyValue.map!(
                a => a.value.map!(b => MutationPointEntry2(fio.toRelativeRoot(a.key),
                b.offset, b.sloc.begin, b.sloc.end, b.mutants))).joiner.array;
        foreach (f; codeMutants.points.byKey) {
            const id = Result.LocalFileId(result.idFile.length);
            result.idFile[f] = id;
            result.fileId[id] = f;
            result.infoId[id] = Result.FileInfo(codeMutants.csFiles[f], codeMutants.lang);
        }

        if (conf.saveCoverage) {
            auto cov = toCoverage(ast, fio, valLoc);
            debug logger.trace(cov);

            foreach (a; cov.points.byKeyValue) {
                if (auto id = a.key in result.idFile) {
                    result.coverage[*id] = a.value;
                }
            }
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

        if (auto localId = file in result.idFile) {
            const fid = FileId(localId.get);

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
    }

    void saveDependencies(ParseFlags flags, AbsolutePath root, Path[] dependencies) @trusted {
        import std.algorithm : cache;
        import std.mmfile;

        auto rootDir = root.dirName;

        foreach (p; dependencies.map!(a => toAbsolutePath(a, rootDir,
                flags.includes, flags.systemIncludes))
                .cache
                .filter!(a => a.hasValue)
                .map!(a => a.orElse(AbsolutePath.init))
                .filter!(a => valLoc.isInsideOutputDir(a))) {
            try {
                result.dependencies ~= DepFile(fio.toRelativeRoot(p), checksum(p));
            } catch (Exception e) {
                logger.trace(e.msg).collectException;
            }
        }

        debug logger.trace(result.dependencies);
    }

    static class Result {
        import dextool.plugin.mutate.backend.analyze.ast : Interval;
        import dextool.plugin.mutate.backend.database.type : SchemataFragment;
        import dextool.plugin.mutate.backend.type : Language, CodeChecksum, SchemataChecksum;

        alias LocalFileId = NamedType!(long, Tag!"LocalFileId", long.init,
                TagStringable, Hashable);
        alias LocalSchemaId = NamedType!(long, Tag!"LocalSchemaId", long.init,
                TagStringable, Hashable);

        MutationPointEntry2[] mutationPoints;

        static struct FileInfo {
            Checksum checksum;
            Language language;
        }

        /// The file that is analyzed, which is a root
        AbsolutePath root;
        Checksum rootCs;

        /// The dependencies the root has.
        DepFile[] dependencies;

        /// The key is the ID from idFile.
        FileInfo[LocalFileId] infoId;

        /// The IDs is unique for *this* analyze, not globally.
        LocalFileId[AbsolutePath] idFile;
        AbsolutePath[LocalFileId] fileId;

        // The FileID used in the metadata is local to this analysis. It has to
        // be remapped when added to the database.
        LineMetadata[] metadata;

        /// Mutant schematas that has been generated.
        SchemataResult.Schemata[AbsolutePath] schematas;

        /// Coverage intervals that can be instrumented.
        Interval[][LocalFileId] coverage;
    }
}

@(
        "shall extract the tag and comment from the input following the pattern NOMUT with optional tag and comment")
unittest {
    import std.regex : regex, matchFirst;
    import unit_threaded.runner.io : writelnUt;

    auto re_nomut = regex(Analyze.rawReNomut);
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
    import libclang_ast.context : ClangContext;
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
    import dextool.plugin.mutate.backend.type : ExitStatus;

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
        db.updateMutationStatus(stId.get, m.toStatus, ExitStatus(0));
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

/// Convert to an absolute path by finding the first match among the compiler flags
Optional!AbsolutePath toAbsolutePath(Path file, AbsolutePath workDir,
        ParseFlags.Include[] includes, SystemIncludePath[] systemIncludes) @trusted nothrow {
    import std.algorithm : map, filter;
    import std.file : exists;
    import std.path : buildPath;

    Optional!AbsolutePath lookup(string dir) nothrow {
        const p = buildPath(dir, file);
        try {
            if (exists(p))
                return some(AbsolutePath(p));
        } catch (Exception e) {
        }
        return none!AbsolutePath;
    }

    {
        auto a = lookup(workDir.toString);
        if (a.hasValue)
            return a;
    }

    foreach (a; includes.map!(a => lookup(a.payload))
            .filter!(a => a.hasValue)) {
        return a;
    }

    foreach (a; systemIncludes.map!(a => lookup(a.value))
            .filter!(a => a.hasValue)) {
        return a;
    }

    return none!AbsolutePath;
}

/** Returns: the root files that need to be re-analyzed because either them or
 * their dependency has changed.
 */
bool[Path] dependencyAnalyze(const AbsolutePath dbPath, FilesysIO fio) @trusted {
    import dextool.cachetools : nullableCache;
    import dextool.plugin.mutate.backend.database : FileId;

    auto db = Database.make(dbPath);

    typeof(return) rval;

    // pessimistic. Add all as needing to be analyzed.
    foreach (a; db.getRootFiles.map!(a => db.getFile(a).get)) {
        rval[a] = false;
    }

    try {
        auto getFileId = nullableCache!(string, FileId, (string p) => db.getFileId(p.Path))(256,
                30.dur!"seconds");
        auto getFileName = nullableCache!(FileId, Path, (FileId id) => db.getFile(id))(256,
                30.dur!"seconds");
        auto getFileDbChecksum = nullableCache!(string, Checksum,
                (string p) => db.getFileChecksum(p.Path))(256, 30.dur!"seconds");
        auto getFileFsChecksum = nullableCache!(AbsolutePath, Checksum, (AbsolutePath p) {
            return checksum(p);
        })(256, 30.dur!"seconds");

        Checksum[Path] dbDeps;
        foreach (a; db.dependencyApi.getAll)
            dbDeps[a.file] = a.checksum;

        const isToolVersionDifferent = db.isToolVersionDifferent(ToolVersion(dextoolBinaryId));
        bool isChanged(T)(T f) {
            if (isToolVersionDifferent) {
                // because the tool version is updated then all files need to
                // be re-analyzed. an update can mean that scheman are
                // improved, mutants has been changed/removed etc. it is
                // unknown. the only way to be sure is to re-analyze all files.
                return true;
            }

            if (f.rootCs != getFileFsChecksum(fio.toAbsoluteRoot(f.root)))
                return true;

            foreach (a; f.deps.filter!(a => getFileFsChecksum(fio.toAbsoluteRoot(a)) != dbDeps[a])) {
                return true;
            }

            return false;
        }

        foreach (f; db.getRootFiles
                .map!(a => db.getFile(a).get)
                .map!(a => tuple!("root", "rootCs", "deps")(a,
                    getFileDbChecksum(a), db.dependencyApi.get(a)))
                .cache
                .filter!(a => isChanged(a))
                .map!(a => a.root)) {
            rval[f] = true;
        }
    } catch (Exception e) {
        logger.warning(e.msg);
    }

    logger.trace("Dependency analyze: ", rval);

    return rval;
}
