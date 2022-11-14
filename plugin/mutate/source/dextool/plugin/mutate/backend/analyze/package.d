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

import core.thread : Thread;
import logger = std.experimental.logger;
import std.algorithm : map, filter, joiner, cache, max;
import std.array : array, appender, empty;
import std.concurrency;
import std.datetime : dur, Duration;
import std.exception : collectException;
import std.functional : toDelegate;
import std.parallelism : TaskPool, totalCPUs;
import std.range : tee, enumerate;
import std.typecons : tuple;

import colorlog;
import my.actor.utility.limiter;
import my.actor;
import my.filter : GlobFilter;
import my.gc.refc;
import my.named_type;
import my.optional;
import my.set;

static import colorlog;

import dextool.utility : dextoolBinaryId;

import dextool.compilation_db : CompileCommandFilter, defaultCompilerFlagFilter, CompileCommandDB,
    ParsedCompileCommandRange, ParsedCompileCommand, ParseFlags, SystemIncludePath;
import dextool.plugin.mutate.backend.analyze.schema_ml : SchemaQ;
import dextool.plugin.mutate.backend.analyze.internal : TokenStream;
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
import dextool.plugin.mutate.type : MutationKind, MutantIdGeneratorConfig;
import dextool.plugin.mutate.config : ConfigCompiler, ConfigAnalyze, ConfigSchema, ConfigCoverage;
import dextool.type : ExitStatusType, AbsolutePath, Path;

version (unittest) {
    import unit_threaded.assertions;
}

alias log = colorlog.log!"analyze";

/** Analyze the files in `frange` for mutations.
 */
ExitStatusType runAnalyzer(const AbsolutePath dbPath, const MutationKind[] userKinds,
        ConfigAnalyze analyzeConf, ConfigCompiler compilerConf,
        ConfigSchema schemaConf, ConfigCoverage covConf,
        ParsedCompileCommandRange frange, ValidateLoc valLoc, FilesysIO fio) @trusted {
    import dextool.plugin.mutate.backend.diff_parser : diffFromStdin, Diff;
    import dextool.plugin.mutate.backend.mutation_type : toInternal;

    auto fileFilter = () {
        try {
            return FileFilter(fio.getOutputDir, analyzeConf.unifiedDiffFromStdin,
                    analyzeConf.unifiedDiffFromStdin ? diffFromStdin : Diff.init);
        } catch (Exception e) {
            log.info(e.msg);
            log.warning("Unable to parse diff");
        }
        return FileFilter.init;
    }();

    bool shouldAnalyze(AbsolutePath p) {
        return analyzeConf.fileMatcher.match(p.toString) && fileFilter.shouldAnalyze(p);
    }

    auto sys = makeSystem;

    auto flowCtrl = sys.spawn(&spawnFlowControl, () {
        const x = analyzeConf.poolSize == 0 ? (totalCPUs + 1) : analyzeConf.poolSize;
        // TODO: investigate further why <4 lead to a livelock of the analyzer.
        return max(x, 4);
    }());

    auto db = refCounted(Database.make(dbPath));

    // if a dependency of a root file has been changed.
    auto changedDeps = dependencyAnalyze(db.get, fio);
    auto schemaQ = SchemaQ(db.get.schemaApi.getMutantProbability);

    auto store = sys.spawn(&spawnStoreActor, flowCtrl, db,
            StoreConfig(analyzeConf, schemaConf, covConf), fio, changedDeps.byKeyValue
            .filter!(a => !a.value)
            .map!(a => a.key)
            .array);
    db.release;
    // it crashes if the store actor try to call dextoolBinaryId. I don't know
    // why... TLS store trashed? But it works, somehow, if I put some writeln
    // inside dextoolBinaryId.
    send(store, Start.init, ToolVersion(dextoolBinaryId));

    sys.spawn(&spawnTestPathActor, store, analyzeConf.testPaths, analyzeConf.testFileMatcher, fio);

    auto kinds = toInternal(userKinds);

    foreach (f; frange.filter!(a => shouldAnalyze(a.cmd.absoluteFile))) {
        try {
            if (auto v = fio.toRelativeRoot(f.cmd.absoluteFile) in changedDeps) {
                if (!(*v || analyzeConf.forceSaveAnalyze))
                    continue;
            }

            // TODO: how to "slow down" if store is working too slow.

            // must dup schemaQ or we run into multithreaded bugs because a
            // SchemaQ have mutable caches internally.  also must allocate on
            // the GC because otherwise they share the same associative array.
            // Don't ask me how that happens because `.dup` should have created
            // a unique one. If you print the address here of `.state` and the
            // receiving end you will see that they are re-used between actors!
            auto sq = new SchemaQ(schemaQ.dup.state);
            auto a = sys.spawn(&spawnAnalyzer, flowCtrl, store, kinds, f, valLoc.dup,
                    fio.dup, AnalyzeConfig(compilerConf, analyzeConf, covConf, sq));
            send(store, StartedAnalyzer.init);
        } catch (Exception e) {
            log.trace(e);
            log.warning(e.msg);
        }
    }

    send(store, DoneStartingAnalyzers.init);

    changedDeps = typeof(changedDeps).init; // free the memory

    auto self = scopedActor;
    bool waiting = true;
    while (waiting) {
        try {
            self.request(store, infTimeout).send(IsDone.init).then((bool x) {
                waiting = !x;
            });
        } catch (ScopedActorException e) {
            logger.warning(e.error);
            return ExitStatusType.Errors;
        }
        () @trusted { Thread.sleep(100.dur!"msecs"); }();
    }

    if (analyzeConf.profile)
        try {
            import std.stdio : writeln;

            writeln(getProfileResult.toString);
        } catch (Exception e) {
            log.warning("Unable to print the profile data: ", e.msg).collectException;
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

struct StartedAnalyzer {
}

struct DoneStartingAnalyzers {
}

/// Number of analyze tasks that has been spawned that the `storeActor` should wait for.
struct AnalyzeCntMsg {
    int value;
}

/// The main thread is waiting for storeActor to send this message.
struct StoreDoneMsg {
}

struct AnalyzeConfig {
    ConfigCompiler compiler;
    ConfigAnalyze analyze;
    ConfigCoverage coverage;
    SchemaQ* sq;
}

struct WaitForToken {
}

struct RunAnalyze {
}

alias AnalyzeActor = typedActor!(void function(WaitForToken), void function(RunAnalyze));

/// Start an analyze of a file
auto spawnAnalyzer(AnalyzeActor.Impl self, FlowControlActor.Address flowCtrl, StoreActor.Address storeAddr,
        Mutation.Kind[] kinds, ParsedCompileCommand fileToAnalyze,
        ValidateLoc vloc, FilesysIO fio, AnalyzeConfig conf) {
    auto st = tuple!("self", "flowCtrl", "storeAddr", "kinds", "fileToAnalyze",
            "vloc", "fio", "conf")(self, flowCtrl, storeAddr, kinds,
            fileToAnalyze, vloc, fio.dup, conf);
    alias Ctx = typeof(st);

    static void wait(ref Ctx ctx, WaitForToken) {
        ctx.self.request(ctx.flowCtrl, infTimeout).send(TakeTokenMsg.init)
            .capture(ctx).then((ref Ctx ctx, Token _) => send(ctx.self, RunAnalyze.init));
    }

    static void run(ref Ctx ctx, RunAnalyze) @safe {
        auto profile = Profile("analyze file " ~ ctx.fileToAnalyze.cmd.absoluteFile);

        bool onlyValidFiles = true;

        try {
            log.tracef("%s begin", ctx.fileToAnalyze.cmd.absoluteFile);
            auto analyzer = Analyze(ctx.kinds, ctx.vloc, ctx.fio,
                    Analyze.Config(ctx.conf.compiler.forceSystemIncludes,
                        ctx.conf.coverage.use, ctx.conf.compiler.allowErrors.get, *ctx.conf.sq));
            analyzer.process(ctx.fileToAnalyze, ctx.conf.analyze.idGenConfig);

            foreach (a; analyzer.result.idFile.byKey) {
                if (!isFileSupported(ctx.fio, a)) {
                    log.warningf(
                            "%s: file not supported. It must be in utf-8 format without a BOM marker");
                    onlyValidFiles = false;
                    break;
                }
            }

            if (onlyValidFiles)
                send(ctx.storeAddr, analyzer.result, Token.init);
            log.tracef("%s end", ctx.fileToAnalyze.cmd.absoluteFile);
        } catch (Exception e) {
            onlyValidFiles = false;
            log.error(e.msg).collectException;
        }

        if (!onlyValidFiles) {
            log.tracef("%s failed", ctx.fileToAnalyze.cmd.absoluteFile).collectException;
            send(ctx.storeAddr, Token.init);
        }

        ctx.self.shutdown;
    }

    self.name = "analyze";
    send(self, WaitForToken.init);
    return impl(self, &run, capture(st), &wait, capture(st));
}

class TestFileResult {
    Duration time;
    TestFile[Checksum] files;
}

alias TestPathActor = typedActor!(void function(Start, StoreActor.Address));

auto spawnTestPathActor(TestPathActor.Impl self, StoreActor.Address store,
        AbsolutePath[] userPaths, GlobFilter matcher, FilesysIO fio) {
    import std.datetime : Clock;
    import std.datetime.stopwatch : StopWatch, AutoStart;
    import std.file : isDir, isFile, dirEntries, SpanMode;
    import my.container.vector;

    auto st = tuple!("self", "matcher", "fio", "userPaths")(self, matcher, fio.dup, userPaths);
    alias Ctx = typeof(st);

    static void start(ref Ctx ctx, Start, StoreActor.Address store) {
        auto profile = Profile("checksum test files");

        auto sw = StopWatch(AutoStart.yes);

        TestFile makeTestFile(const AbsolutePath file) {
            auto cs = checksum(ctx.fio.makeInput(file).content[]);
            return TestFile(TestFilePath(ctx.fio.toRelativeRoot(file)),
                    TestFileChecksum(cs), Clock.currTime);
        }

        auto paths = vector(ctx.userPaths);

        auto tfiles = new TestFileResult;
        scope (exit)
            tfiles.time = sw.peek;

        while (!paths.empty) {
            try {
                if (isDir(paths.front)) {
                    log.trace("  Test directory ", paths.front);
                    foreach (a; dirEntries(paths.front, SpanMode.shallow).map!(
                            a => AbsolutePath(a.name))) {
                        paths.put(a);
                    }
                } else if (isFile(paths.front) && ctx.matcher.match(paths.front)) {
                    log.trace("  Test saved ", paths.front);
                    auto t = makeTestFile(paths.front);
                    tfiles.files[t.checksum.get] = t;
                }
            } catch (Exception e) {
                log.warning(e.msg).collectException;
            }

            paths.popFront;
        }

        log.infof("Found %s test files", tfiles.files.length).collectException;
        send(store, tfiles);
        ctx.self.shutdown;
    }

    self.name = "test path";
    send(self, Start.init, store);
    return impl(self, &start, capture(st));
}

struct Start {
}

struct IsDone {
}

struct SetDone {
}

// Check if it is time to post process
struct CheckPostProcess {
}
// Run the post processning.
struct PostProcess {
}

struct StoreConfig {
    ConfigAnalyze analyze;
    ConfigSchema schema;
    ConfigCoverage coverage;
}

alias StoreActor = typedActor!(void function(Start, ToolVersion), bool function(IsDone),
        void function(StartedAnalyzer), void function(Analyze.Result, Token), // failed to analyze the file, but still returning the token.
        void function(Token),
        void function(DoneStartingAnalyzers), void function(TestFileResult),
        void function(CheckPostProcess), void function(PostProcess),);

/// Store the result of the analyze.
auto spawnStoreActor(StoreActor.Impl self, FlowControlActor.Address flowCtrl,
        RefCounted!(Database) db, StoreConfig conf, FilesysIO fio, Path[] rootFiles) @trusted {
    static struct State {
        import dextool.plugin.mutate.backend.type : CodeMutant;

        // conditions governing when the analyze is done
        // if all analyze workers have been started and thus it is time to
        // start checking if startedAnalyzers == savedResult.
        bool doneStarting;
        // number of analyze workers that have been started.
        int startedAnalyzers;
        // number of saved results.
        int savedResult;
        // if checksums of all test files have been saved to disk
        bool savedTestFileResult;

        // if a file is modified then the timeout context need to be reset
        bool resetTimeoutCtx;

        /// Set when the whole analyze process is done and all results are saved to the database.
        bool isDone;

        bool isToolVersionDifferent;

        // only save new mutants. assuming that it is faster to check if the
        // mutants have been saved before than to go through multiple sql
        // queries.
        Set!CodeMutant saved;

        // files that have been saved to the database.
        Set!AbsolutePath savedFiles;
        // clearing a file should only happen once.
        Set!AbsolutePath clearedFiles;
    }

    auto st = tuple!("self", "db", "state", "fio", "conf", "rootFiles", "flowCtrl")(self,
            db, refCounted(State.init), fio.dup, conf, rootFiles, flowCtrl);
    alias Ctx = typeof(st);

    static void start(ref Ctx ctx, Start, ToolVersion toolVersion) {
        log.trace("starting store actor");

        ctx.state.get.isToolVersionDifferent = ctx.db.get.isToolVersionDifferent(toolVersion);

        if (ctx.conf.analyze.fastDbStore) {
            log.info(
                    "Turning OFF sqlite3 synchronization protection to improve the write performance");
            log.warning("Do NOT interrupt dextool in any way because it may corrupt the database");
            ctx.db.get.run("PRAGMA synchronous = OFF");
            ctx.db.get.run("PRAGMA journal_mode = MEMORY");
        }

        send(ctx.self, CheckPostProcess.init);
        log.trace("store actor active");
    }

    static bool isDone(ref Ctx ctx, IsDone) {
        return ctx.state.get.isDone;
    }

    static void startedAnalyzers(ref Ctx ctx, StartedAnalyzer) {
        ctx.state.get.startedAnalyzers++;
    }

    static void doneStartAnalyzers(ref Ctx ctx, DoneStartingAnalyzers) {
        ctx.state.get.doneStarting = true;
    }

    static void failedFileAnalyze(ref Ctx ctx, Token) {
        send(ctx.flowCtrl, ReturnTokenMsg.init);
        // a failed file has to count as well.
        ctx.state.get.savedResult++;
    }

    static void checkPostProcess(ref Ctx ctx, CheckPostProcess) {
        if (ctx.state.get.doneStarting && ctx.state.get.savedTestFileResult
                && (ctx.state.get.startedAnalyzers == ctx.state.get.savedResult))
            send(ctx.self, PostProcess.init);
        else
            delayedSend(ctx.self, delay(500.dur!"msecs"), CheckPostProcess.init);
    }

    static void savedTestFileResult(ref Ctx ctx, TestFileResult result) {
        auto profile = Profile("save test files");

        ctx.state.get.savedTestFileResult = true;

        Set!Checksum old;

        auto t = ctx.db.get.transaction;

        foreach (a; ctx.db.get.testFileApi.getTestFiles) {
            old.add(a.checksum.get);
            if (a.checksum.get !in result.files) {
                log.info("Removed test file ", a.file.get.toString);
                ctx.db.get.testFileApi.removeFile(a.file);
            }
        }

        foreach (a; result.files.byValue.filter!(a => a.checksum.get !in old)) {
            log.info("Saving test file ", a.file.get.toString);
            ctx.db.get.testFileApi.put(a);
        }

        t.commit;

        send(ctx.self, CheckPostProcess.init);
    }

    static void save(ref Ctx ctx, Analyze.Result result, Token) {
        import dextool.cachetools : nullableCache;
        import dextool.plugin.mutate.backend.database : LineMetadata, FileId, LineAttr, NoMut;
        import dextool.plugin.mutate.backend.type : Language;

        auto profile = Profile("save " ~ result.root);

        // by returning the token now another file analyze can start while we
        // are saving the current one.
        send(ctx.flowCtrl, ReturnTokenMsg.init);

        ctx.state.get.savedResult++;
        log.infof("Analyzed %s/%s %s", ctx.state.get.savedResult,
                ctx.state.get.startedAnalyzers, result.root);

        auto getFileId = nullableCache!(string, FileId, (string p) => ctx.db.get.getFileId(p.Path))(256,
                10.dur!"seconds");
        auto getFileDbChecksum = nullableCache!(string, Checksum,
                (string p) => ctx.db.get.getFileChecksum(p.Path))(256, 30.dur!"seconds");
        auto getFileFsChecksum = nullableCache!(string, Checksum, (string p) {
            return checksum(ctx.fio.makeInput(AbsolutePath(Path(p))).content[]);
        })(256, 10.dur!"seconds");

        static struct Files {
            Checksum[Path] value;

            this(ref Database db) {
                foreach (a; db.getDetailedFiles) {
                    value[a.file] = a.fileChecksum;
                }
            }
        }

        auto trans = ctx.db.get.transaction;

        // keeps both absolute and relative because then less transformations
        // are needed. mutation points use relative...
        Set!Path skipFile;

        // mark files that have an unchanged checksum as "already saved"
        foreach (f; result.idFile.byKey.filter!(a => a !in ctx.state.get.clearedFiles)) {
            const relp = ctx.fio.toRelativeRoot(f);

            if (getFileDbChecksum(relp) != getFileFsChecksum(f)
                    || ctx.conf.analyze.forceSaveAnalyze || ctx.state.get.isToolVersionDifferent) {
                // this is critical in order to remove old data about a file.
                if (f !in ctx.state.get.clearedFiles) {
                    ctx.db.get.removeFile(relp);
                    ctx.state.get.clearedFiles.add(f);
                }
            } else {
                log.info("Unchanged ".color(Color.yellow), f);
                ctx.state.get.savedFiles.add(f);
                skipFile.add(f);
                skipFile.add(relp);
            }
        }

        {
            bool isChanged = ctx.state.get.isToolVersionDifferent;

            foreach (f; result.idFile.byKey.filter!(a => a !in skipFile
                    && a !in ctx.state.get.savedFiles)) {
                isChanged = true;
                log.info("Saving ".color(Color.green), f);

                const relp = ctx.fio.toRelativeRoot(f);
                const info = result.infoId[result.idFile[f]];
                ctx.db.get.fileApi.put(relp, info.checksum, info.language, f == result.root);

                ctx.state.get.savedFiles.add(f);
            }

            if (result.root !in ctx.state.get.savedFiles) {
                // this occurs when the file is e.g. a unittest that uses a
                // header only library. The unittests are not mutated thus
                // no mutation points exists in them but we want dextool to
                // still, if possible, track the unittests for changes.
                isChanged = true;
                const relp = ctx.fio.toRelativeRoot(result.root);
                ctx.db.get.removeFile(relp);
                // the language do not matter because it is a file without
                // any mutants.
                ctx.db.get.fileApi.put(relp, result.rootCs, Language.init, true);
                ctx.state.get.savedFiles.add(ctx.fio.toAbsoluteRoot(result.root));
            }

            {
                auto app = appender!(MutationPointEntry2[])();
                foreach (mp; result.mutationPoints.filter!(a => a.file !in skipFile
                        && a.cm !in ctx.state.get.saved)) {
                    app.put(mp);
                }
                // only block new mutants of the same source code change after
                // a whole "pass" because the same mutant kind can result in
                // the same CodeChecksum.
                ctx.state.get.saved.add(app.data.map!(a => a.cm));
                ctx.db.get.mutantApi.put(app.data, ctx.fio.getOutputDir);
            }

            // must always update dependencies because they may not contain
            // mutants. Only files that are changed and contain mutants
            // trigger isChanged to be true.
            try {
                // not all files are tracked thus this may throw an exception.
                ctx.db.get.dependencyApi.set(ctx.fio.toRelativeRoot(result.root),
                        result.dependencies);
            } catch (Exception e) {
            }

            ctx.state.get.resetTimeoutCtx = ctx.state.get.resetTimeoutCtx || isChanged;

            if (isChanged) {
                foreach (a; result.coverage.byKeyValue) {
                    const fid = getFileId(ctx.fio.toRelativeRoot(result.fileId[a.key]));
                    if (!fid.isNull) {
                        ctx.db.get.coverageApi.clearCoverageMap(fid.get);
                        ctx.db.get.coverageApi.putCoverageMap(fid.get, a.value);
                    }
                }

                saveSchemaFragments(ctx.db.get, ctx.fio, result.schematas);
            }
        }

        {
            Set!long printed;
            auto app = appender!(LineMetadata[])();
            foreach (md; result.metadata) {
                const localId = Analyze.Result.LocalFileId(md.id.get);
                // transform the ID from local to global.
                const fid = getFileId(ctx.fio.toRelativeRoot(result.fileId[localId]));
                if (fid.isNull && !printed.contains(md.id.get)) {
                    printed.add(md.id.get);
                    log.info("File with suppressed mutants (// NOMUT) not in the database: ",
                            result.fileId[localId]).collectException;
                } else if (!fid.isNull) {
                    app.put(LineMetadata(fid.get, md.line, md.attr));
                }
            }
            ctx.db.get.metaDataApi.put(app.data);
        }

        trans.commit;

        send(ctx.self, CheckPostProcess.init);
    }

    static void postProcess(ref Ctx ctx, PostProcess) {
        import dextool.plugin.mutate.backend.test_mutant.timeout : resetTimeoutContext;

        if (ctx.state.get.isDone)
            return;

        ctx.state.get.isDone = true;

        void fastDbOff() {
            if (!ctx.conf.analyze.fastDbStore)
                return;
            ctx.db.get.run("PRAGMA synchronous = ON");
            ctx.db.get.run("PRAGMA journal_mode = DELETE");
        }

        void pruneFiles() {
            import std.path : buildPath;

            auto profile = Profile("prune files");

            log.info("Pruning the database of dropped files");
            auto files = ctx.db.get.getFiles.map!(a => ctx.fio.toAbsoluteRoot(a)).toSet;

            foreach (f; files.setDifference(ctx.state.get.savedFiles).toRange) {
                log.info("Removing ".color(Color.red), f);
                ctx.db.get.removeFile(ctx.fio.toRelativeRoot(f));
            }
        }

        void addRoots() {
            if (ctx.conf.analyze.forceSaveAnalyze || ctx.state.get.isToolVersionDifferent)
                return;

            // add root files and their dependencies that has not been analyzed because nothing has changed.
            // By adding them they are not removed.

            auto profile = Profile("add roots and dependencies");
            foreach (a; ctx.rootFiles) {
                auto p = ctx.fio.toAbsoluteRoot(a);
                if (p !in ctx.state.get.savedFiles) {
                    ctx.state.get.savedFiles.add(p);
                    // fejk text for the user to tell them that yes, the files have
                    // been analyzed.
                    log.info("Analyzing ", a);
                    log.info("Unchanged ".color(Color.yellow), a);
                }
            }
            foreach (a; ctx.rootFiles.map!(a => ctx.db.get.dependencyApi.get(a)).joiner) {
                ctx.state.get.savedFiles.add(ctx.fio.toAbsoluteRoot(a));
            }
        }

        void pruneSchemaMl() {
            auto profile = Profile("prune schema_ml model");
            log.info("Prune schema ML model");

            Set!Checksum files;
            foreach (a; ctx.db.get.getFiles)
                files.add(checksum(cast(const(ubyte)[]) a.toString));

            foreach (a; ctx.db.get.schemaApi.getMutantProbability.byKey.filter!(a => a !in files)) {
                logger.trace("schema model. Dropping ", a);
                ctx.db.get.schemaApi.removeMutantProbability(a);
            }
        }

        auto trans = ctx.db.get.transaction;

        addRoots;

        if (ctx.state.get.resetTimeoutCtx) {
            log.info("Resetting timeout context");
            resetTimeoutContext(ctx.db.get);
        }

        log.info("Updating metadata");
        ctx.db.get.metaDataApi.updateMetadata;

        if (ctx.conf.analyze.prune) {
            pruneFiles();
            {
                auto profile = Profile("prune dependencies");
                log.info("Prune dependencies");
                ctx.db.get.dependencyApi.cleanup;
            }
            {
                auto profile = Profile("remove orphaned mutants");
                log.info("Removing orphaned mutants");
                auto progress = (size_t i, size_t total, const Duration avgRemoveTime,
                        const Duration timeLeft, SysTime predDoneAt) {
                    logger.infof("%s/%s removed (average %sms) (%s) (%s)", i,
                            total, avgRemoveTime, timeLeft, predDoneAt.toSimpleString);
                };
                auto done = (size_t total) {
                    logger.infof(total > 0, "%1$s/%1$s removed", total);
                };
                ctx.db.get.mutantApi.removeOrphanedMutants(progress.toDelegate, done.toDelegate);
            }
            try {
                pruneSchemaMl;
            } catch (Exception e) {
                logger.warning(e.msg);
                logger.warning("Unable to prune schema ML model");
            }
        }

        log.info("Updating manually marked mutants");
        updateMarkedMutants(ctx.db.get);
        printLostMarkings(ctx.db.get.markMutantApi.getLostMarkings);

        if (ctx.state.get.isToolVersionDifferent) {
            log.info("Updating tool version");
            ctx.db.get.updateToolVersion(ToolVersion(dextoolBinaryId));
        }

        log.info("Committing changes");
        trans.commit;
        log.info("Ok".color(Color.green));

        fastDbOff();

        if (ctx.state.get.isToolVersionDifferent) {
            auto profile = Profile("compact");
            log.info("Compacting the database");
            ctx.db.get.vacuum;
        }
    }

    self.name = "store";

    auto s = impl(self, &start, capture(st), &isDone, capture(st),
            &startedAnalyzers, capture(st), &save, capture(st), &doneStartAnalyzers,
            capture(st), &savedTestFileResult, capture(st), &checkPostProcess,
            capture(st), &postProcess, capture(st), &failedFileAnalyze, capture(st));
    s.exceptionHandler = toDelegate(&logExceptionHandler);
    return s;
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
        SchemaQ sq;
    }

    private {
        static immutable rawReNomut = `^((//)|(/\*+))\s*NOMUT(?P<type>\w*)\s*(\((?P<tag>.*)\))?\s*((?P<comment>.*)\*/|(?P<comment>.*))?`;

        Regex!char re_nomut;
        ValidateLoc valLoc;
        FilesysIO fio;

        Result result;

        Config conf;

        Mutation.Kind[] kinds;
    }

    this(Mutation.Kind[] kinds, ValidateLoc valLoc, FilesysIO fio, Config conf) @trusted {
        this.kinds = kinds;
        this.valLoc = valLoc;
        this.fio = fio;
        this.re_nomut = regex(rawReNomut);
        this.result = new Result;
        this.conf = conf;
    }

    void process(ParsedCompileCommand commandsForFileToAnalyze, MutantIdGeneratorConfig idGenConf) @safe {
        import std.file : exists;

        commandsForFileToAnalyze.flags.forceSystemIncludes = conf.forceSystemIncludes;

        try {
            if (!exists(commandsForFileToAnalyze.cmd.absoluteFile)) {
                log.warningf("Failed to analyze %s. Do not exist",
                        commandsForFileToAnalyze.cmd.absoluteFile);
                return;
            }
        } catch (Exception e) {
            log.warning(e.msg);
            return;
        }

        result.root = commandsForFileToAnalyze.cmd.absoluteFile;

        try {
            result.rootCs = checksum(result.root);

            auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
            scope tstream = new TokenStreamImpl(ctx);

            analyzeForMutants(commandsForFileToAnalyze, result.root, ctx, tstream, idGenConf);
            foreach (f; result.fileId.byValue)
                analyzeForComments(f, tstream);
        } catch (Exception e) {
            () @trusted { log.trace(e); }();
            log.info(e.msg);
            log.error("failed analyze of ",
                    commandsForFileToAnalyze.cmd.absoluteFile).collectException;
        }
    }

    void analyzeForMutants(ParsedCompileCommand commandsForFileToAnalyze, AbsolutePath fileToAnalyze,
            ref ClangContext ctx, scope TokenStream tstream, MutantIdGeneratorConfig idGenConf) @safe {
        import my.gc.refc : RefCounted;
        import dextool.plugin.mutate.backend.analyze.ast : Ast;
        import dextool.plugin.mutate.backend.analyze.pass_clang;
        import dextool.plugin.mutate.backend.analyze.pass_coverage;
        import dextool.plugin.mutate.backend.analyze.pass_filter;
        import dextool.plugin.mutate.backend.analyze.pass_mutant;
        import dextool.plugin.mutate.backend.analyze.pass_schemata;
        import libclang_ast.check_parse_result : hasParseErrors, logDiagnostic;

        log.info("Analyzing ", fileToAnalyze);
        RefCounted!(Ast) ast;
        {
            auto tu = ctx.makeTranslationUnit(fileToAnalyze,
                    commandsForFileToAnalyze.flags.completeFlags);
            if (tu.hasParseErrors) {
                logDiagnostic(tu);
                log.warningf("Compile error in %s", fileToAnalyze);
                if (!conf.allowErrors) {
                    log.warning("Skipping");
                    return;
                }
            }

            auto res = toMutateAst(tu.cursor, fio, valLoc);
            ast = res.ast;
            saveDependencies(commandsForFileToAnalyze.flags, result.root, res.dependencies);
            log!"analyze.pass_clang".trace(ast.get.toString);
        }

        auto codeMutants = () {
            auto mutants = toMutants(ast.ptr, fio, valLoc, kinds);
            log!"analyze.pass_mutant".trace(mutants);

            log!"analyze.pass_filter".trace("filter mutants");
            mutants = filterMutants(fio, mutants);
            log!"analyze.pass_filter".trace(mutants);

            return toCodeMutants(mutants, fio, tstream, idGenConf);
        }();
        debug logger.trace(codeMutants);

        {
            auto schemas = toSchemata(ast.ptr, fio, codeMutants, conf.sq);
            log!"analyze.pass_schema".trace(schemas);
            log.tracef("path dedup count:%s length_acc:%s",
                    ast.get.paths.count, ast.get.paths.lengthAccum);

            result.schematas = schemas.getFragments;
        }

        {
            auto app = appender!(MutationPointEntry2[])();
            foreach (a; codeMutants.points.byKeyValue) {
                foreach (b; a.value) {
                    app.put(MutationPointEntry2(fio.toRelativeRoot(a.key),
                            b.offset, b.sloc.begin, b.sloc.end, b.mutant));
                }
            }
            result.mutationPoints = app.data;
        }
        foreach (f; codeMutants.points.byKey) {
            const id = Result.LocalFileId(result.idFile.length);
            result.idFile[f] = id;
            result.fileId[id] = f;
            result.infoId[id] = Result.FileInfo(codeMutants.csFiles[f], codeMutants.lang);
        }

        if (conf.saveCoverage) {
            auto cov = toCoverage(ast.ptr, fio, valLoc);
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
    void analyzeForComments(AbsolutePath file, scope TokenStream tstream) @safe {
        import std.algorithm : filter;
        import clang.c.Index : CXTokenKind;
        import dextool.plugin.mutate.backend.database : LineMetadata, FileId, LineAttr, NoMut;

        if (auto localId = file in result.idFile) {
            const fid = FileId(localId.get);

            auto mdata = appender!(LineMetadata[])();

            int sectionStart = -1;
            LineMetadata sectionData;

            foreach (t; tstream.getTokens(file).filter!(a => a.kind == CXTokenKind.comment)) {
                auto m = matchFirst(t.spelling, re_nomut);

                if (m.whichPattern == 0)
                    continue;

                switch (m["type"]) {
                case "BEGIN":
                    if (sectionStart == -1) {
                        sectionStart = t.loc.line;
                        sectionData = LineMetadata(fid, t.loc.line + 1,
                                LineAttr(NoMut(m["tag"], m["comment"])));
                    } else {
                        logger.warningf("NOMUT: Found multiple NOMUTBEGIN in a row! Will use the first one on line %s",
                                sectionStart);
                    }
                    break;
                case "END":
                    if (sectionStart == -1) {
                        logger.warningf("NOMUT: Found a NOMUTEND without a NOMUTBEGIN on line %s! Ignoring",
                                t.loc.line);
                    } else {
                        foreach (const i; sectionStart .. t.loc.line) {
                            sectionData.line = i;
                            () @trusted { mdata.put(sectionData); }();
                            log.tracef("NOMUT found at %s:%s:%s", file, t.loc.line, t.loc.column);
                        }

                        sectionStart = -1;
                        sectionData = LineMetadata.init;
                    }
                    break;
                case "NEXT":
                    () @trusted {
                        mdata.put(LineMetadata(fid, t.loc.line + 1,
                                LineAttr(NoMut(m["tag"], m["comment"]))));
                    }();
                    log.tracef("NOMUT ON NEXT LINE found at %s:%s:%s", file,
                            t.loc.line, t.loc.column);
                    break;
                default:
                    () @trusted {
                        mdata.put(LineMetadata(fid, t.loc.line,
                                LineAttr(NoMut(m["tag"], m["comment"]))));
                    }();
                    log.tracef("NOMUT found at %s:%s:%s", file, t.loc.line, t.loc.column);
                    break;
                }
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
                log.trace(e.msg).collectException;
            }
        }

        log.trace(result.dependencies);
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
        SchemataResult.Fragments[AbsolutePath] schematas;

        /// Coverage intervals that can be instrumented.
        Interval[][LocalFileId] coverage;
    }
}

@(
        "shall extract the tag and comment from the input following the pattern NOMUT with optional tag and comment")
unittest {
    import std.algorithm : canFind;
    import std.format : format;
    import std.regex : regex, matchFirst;
    import unit_threaded.runner.io : writelnUt;

    auto reNomut = regex(Analyze.rawReNomut);
    const types = ["NOMUT", "NOMUTBEGIN", "NOMUTEND", "NOMUTNEXT"];
    auto okParseTypes = ["", "BEGIN", "END", "NEXT"];
    // NOMUT in other type of comments should NOT match.
    foreach (line; [
            "/// %s", "// stuff with %s in it", "/* stuff with %s in it */"
        ]) {
        foreach (type; types) {
            matchFirst(format(line, type), reNomut).whichPattern.shouldEqual(0);
        }
    }

    foreach (line; ["//%s", "// %s", "/*%s*/", "/* %s */", "/**%s*/"]) {
        foreach (type; types) {
            auto m = matchFirst(format(line, type), reNomut);
            m.whichPattern.shouldEqual(1);
            m["comment"].shouldEqual("");
            m["tag"].shouldEqual("");
        }
    }

    foreach (line; ["//%s (my tag)", "// %s (my tag)", "/* %s (my tag) */",]) {
        foreach (type; types) {
            auto m = matchFirst(format(line, type), reNomut);
            m.whichPattern.shouldEqual(1);
            m["comment"].shouldEqual("");
            m["tag"].shouldEqual("my tag");
        }
    }

    // TODO: should work but doesn't.... : "/* %s my comment */"
    foreach (line; ["//%s my comment", "// %s my comment"]) {
        foreach (type; types) {
            auto m = matchFirst(format(line, type), reNomut);
            m.whichPattern.shouldEqual(1);
            okParseTypes.canFind(m["type"]).shouldBeGreaterThan(0);
            m["comment"].shouldEqual("my comment");
            m["tag"].shouldEqual("");
        }
    }

    foreach (line; ["//%s (my tag) my comment", "// %s (my tag) my comment"]) {
        foreach (type; types) {
            auto m = matchFirst(format(line, type), reNomut);
            m.whichPattern.shouldEqual(1);
            okParseTypes.canFind(m["type"]).shouldBeGreaterThan(0);
            m["comment"].shouldEqual("my comment");
            m["tag"].shouldEqual("my tag");
        }
    }
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

    Token[] getTokens(Path p) scope {
        return tokenize(*ctx, p);
    }

    Token[] getFilteredTokens(Path p) scope {
        import clang.c.Index : CXTokenKind;

        // Filter a stream of tokens for those that should affect the checksum.
        return tokenize(*ctx, p).filter!(a => a.kind != CXTokenKind.comment).array;
    }
}

/** Update the connection between the marked mutants and their mutation status
 * id and mutation id.
 */
void updateMarkedMutants(ref Database db) @trusted {
    import dextool.plugin.mutate.backend.database.type : MutationStatusId,
        toMutationStatusId, toChecksum;
    import dextool.plugin.mutate.backend.type : ExitStatus;

    void update(MarkedMutant m) {
        const stId = toMutationStatusId(m.statusChecksum);
        db.markMutantApi.remove(m.statusChecksum);
        db.markMutantApi.mark(m.path, m.sloc, stId, m.statusChecksum,
                m.toStatus, m.rationale, m.mutText);
        db.mutantApi.update(stId, m.toStatus, ExitStatus(0));
    }

    // find those marked mutants that have a checksum that is different from
    // the mutation status the marked mutant is related to. If possible change
    // the relation to the correct mutation status id.
    foreach (m; db.markMutantApi
            .getMarkedMutants
            .map!(a => tuple(a, toChecksum(a.statusId)))
            .filter!(a => a[0].statusChecksum != a[1])) {
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
            m.statusId.get.to!string, m.path, m.sloc.line.to!string,
            m.sloc.column.to!string, m.toStatus.to!string, m.rationale.get
        ];
        tbl.put(r);
    }
    log.warning("Marked mutants was lost");
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
bool[Path] dependencyAnalyze(ref Database db, FilesysIO fio) @trusted {
    import dextool.cachetools : nullableCache;
    import dextool.plugin.mutate.backend.database : FileId;

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
        log.warning(e.msg);
    }

    log.trace("Dependency analyze: ", rval);

    return rval;
}

/// Only utf-8 files are supported
bool isFileSupported(FilesysIO fio, AbsolutePath p) @safe {
    import std.algorithm : among;
    import std.encoding : getBOM, BOM;

    auto entry = fio.makeInput(p).content.getBOM();
    const res = entry.schema.among(BOM.utf8, BOM.none);

    if (res == 1)
        log.warningf("%s has a utf-8 BOM marker. It will make all coverage and scheman fail to compile",
                p);

    return res != 0;
}

void saveSchemaFragments(ref Database db, FilesysIO fio,
        ref SchemataResult.Fragments[AbsolutePath] fragments) {
    import std.typecons : tuple;
    import dextool.plugin.mutate.backend.database.type : SchemaFragmentV2, toMutationStatusId;

    foreach (a; fragments.byKeyValue
            .map!(a => tuple!("fileId",
                "fragments")(db.getFileId(fio.toRelativeRoot(a.key)), a.value))
            .filter!(a => !a.fileId.isNull)) {
        // TODO: SchemaFragmentV2 and SchemataResult.Fragment are pretty
        // similare to each other. Only CodeMutant is different.
        db.schemaApi.putFragments(a.fileId.get,
                a.fragments.fragments.map!(a => SchemaFragmentV2(a.offset,
                    a.text, a.mutants.map!(a => a.id.toMutationStatusId).array)).array);
    }
}
