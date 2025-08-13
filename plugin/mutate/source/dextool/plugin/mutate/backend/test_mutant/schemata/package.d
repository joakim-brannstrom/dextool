/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.test_mutant.schemata;

import logger = std.experimental.logger;
import std.algorithm : sort, map, filter, among, sum;
import std.array : empty, array, appender;
import std.conv : to;
import std.datetime : Duration, dur, Clock, SysTime;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.exception : collectException;
import std.format : format;
import std.format : formattedWrite, format;
import std.sumtype;
import std.typecons : Tuple, tuple, Nullable;

import blob_model;
import colorlog;
import miniorm : spinSql, silentLog;
import my.actor;
import my.container.vector;
import my.gc.refc;
import my.optional;
import my.path;
import my.set;
import proc : DrainElement;

import dextool.plugin.mutate.backend.analyze.schema_ml : SchemaQ, SchemaSizeQ, SchemaStatus;
import dextool.plugin.mutate.backend.analyze.utility;
import dextool.plugin.mutate.backend.database : MutationStatusId, Database,
    spinSql, SchemataId, Schemata, FileId, SchemataFragment;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.test_mutant.common : TestCaseAnalyzer,
    TestStopCheck, MutationTestResult, MutantTimeProfile, PrintCompileOnFailure;
import dextool.plugin.mutate.backend.test_mutant.common_actors : DbSaveActor, StatActor;
import dextool.plugin.mutate.backend.test_mutant.test_cmd_runner : TestRunner, TestResult;
import dextool.plugin.mutate.backend.test_mutant.timeout : TimeoutFsm, TimeoutConfig;
import dextool.plugin.mutate.backend.type : Language, SourceLoc, Offset,
    SourceLocRange, CodeMutant, SchemataChecksum, Mutation, TestCase, Checksum;
import dextool.plugin.mutate.config : ConfigSchema;
import dextool.plugin.mutate.type : TestCaseAnalyzeBuiltin, ShellCommand,
    UserRuntime, SchemaRuntime;

static import dextool.plugin.mutate.backend.test_mutant.schemata.load;
import dextool.plugin.mutate.backend.test_mutant.schemata.test;
import dextool.plugin.mutate.backend.test_mutant.schemata.builder;

@safe:

private {
    struct Init {
    }

    struct GenSchema {
    }

    struct RunSchema {
    }

    struct UpdateWorkList {
    }

    struct MarkMsg {
    }

    struct InjectAndCompile {
    }

    struct ScheduleTestMsg {
    }

    struct RestoreMsg {
    }

    struct StartTestMsg {
    }

    struct CheckStopCondMsg {
    }

    struct Stop {
    }
}

struct IsDone {
}

struct GetDoneStatus {
}

struct FinalResult {
    enum Status {
        noSchema,
        fatalError,
        invalidSchema,
        ok
    }

    Status status;
    int alive;
}

// dfmt off
alias SchemaActor = typedActor!(
    void function(Init, AbsolutePath database, ShellCommand, Duration),
    /// Generate a schema, if possible
    void function(GenSchema),
    void function(RunSchema, SchemataBuilder.ET, InjectIdResult),
    /// Quary the schema actor to see if it is done
    bool function(IsDone),
    /// Update the list of mutants that are still in the worklist.
    void function(UpdateWorkList, bool),
    FinalResult function(GetDoneStatus),
    /// Save the result of running the schema to the DB.
    void function(SchemaTestResult),
    void function(MarkMsg, FinalResult.Status),
    /// Inject the schema in the source code and compile it.
    void function(InjectAndCompile),
    /// Restore the source code.
    void function(RestoreMsg),
    /// Start running the schema.
    void function(StartTestMsg),
    void function(ScheduleTestMsg),
    void function(CheckStopCondMsg),
    // Queue up a msg that set isRunning to false. Convenient to ensure that a
    // RestoreMsg has been processed before setting to false.
    void function(Stop),
    );
// dfmt on

auto spawnSchema(SchemaActor.Impl self, FilesysIO fio, ref TestRunner runner,
        AbsolutePath dbPath, TestCaseAnalyzer testCaseAnalyzer,
        ConfigSchema conf, TestStopCheck stopCheck, ShellCommand buildCmd, Duration buildCmdTimeout,
        DbSaveActor.Address dbSave, StatActor.Address stat, TimeoutConfig timeoutConf) @trusted {

    static struct State {
        TestStopCheck stopCheck;
        DbSaveActor.Address dbSave;
        StatActor.Address stat;
        TimeoutConfig timeoutConf;
        FilesysIO fio;
        TestRunner runner;
        TestCaseAnalyzer analyzer;
        ConfigSchema conf;

        dextool.plugin.mutate.backend.test_mutant.schemata.load.LoadCtrlActor.Address loadCtrl;

        GenSchemaActor.Address genSchema;
        SchemaSizeQUpdateActor.Address sizeQUpdater;

        ShellCommand buildCmd;
        Duration buildCmdTimeout;

        SchemataBuilder.ET activeSchema;
        enum ActiveSchemaCheck {
            noMutantTested,
            testing,
            triggerRestoreOnce,
        }
        // used to detect a corner case which is that no mutant in the schema is in the whitelist.
        ActiveSchemaCheck activeSchemaCheck;
        Set!Checksum usedScheman;

        AbsolutePath[] modifiedFiles;

        InjectIdResult injectIds;

        ScheduleTest scheduler;

        Set!MutationStatusId whiteList;

        Duration compileTime;

        int alive;

        bool hasFatalError;

        bool isRunning;
    }

    auto st = tuple!("self", "state", "db")(self, refCounted(State(stopCheck, dbSave, stat,
            timeoutConf, fio.dup, runner.dup, testCaseAnalyzer, conf)), Database.make());
    alias Ctx = typeof(st);

    static void init_(ref Ctx ctx, Init _, AbsolutePath dbPath,
            ShellCommand buildCmd, Duration buildCmdTimeout) nothrow {
        import dextool.plugin.mutate.backend.database : dbOpenTimeout;

        try {
            ctx.db = spinSql!(() => Database.make(dbPath), logger.trace)(dbOpenTimeout);

            ctx.state.buildCmd = buildCmd;
            ctx.state.buildCmdTimeout = buildCmdTimeout;

            ctx.state.timeoutConf.timeoutScaleFactor = ctx.state.conf.timeoutScaleFactor;
            logger.tracef("Timeout Scale Factor: %s", ctx.state.timeoutConf.timeoutScaleFactor);
            ctx.state.runner.timeout = ctx.state.timeoutConf.value;

            // ctx.state.loadCtrl = ctx.self.homeSystem.spawn(
            //         &dextool.plugin.mutate.backend.test_mutant.schemata.load.spawnLoadCtrlActor,
            //         dextool.plugin.mutate.backend.test_mutant.schemata.load.TargetLoad(
            //             ctx.state.stopCheck.getLoadThreshold));
            // linkTo(ctx.self, ctx.state.loadCtrl);

            ctx.state.scheduler = () {
                TestMutantActor.Address[] testers;
                foreach (_0; 0 .. ctx.state.conf.parallelMutants) {
                    auto a = ctx.self.homeSystem.spawn(&spawnTestMutant,
                            ctx.state.runner.dup, ctx.state.analyzer);
                    a.linkTo(ctx.self.address);
                    testers ~= a;
                }
                return ScheduleTest(testers);
            }();

            ctx.state.sizeQUpdater = ctx.self.homeSystem.spawn(&spawnSchemaSizeQ,
                    getSchemaSizeQ(ctx.db, ctx.state.conf.mutantsPerSchema.get,
                        ctx.state.conf.minMutantsPerSchema.get), ctx.state.dbSave);
            linkTo(ctx.self, ctx.state.sizeQUpdater);

            ctx.state.genSchema = ctx.self.homeSystem.spawn(&spawnGenSchema,
                    dbPath, ctx.state.conf, ctx.state.sizeQUpdater);
            linkTo(ctx.self, ctx.state.genSchema);

            send(ctx.self, UpdateWorkList.init, true);
            send(ctx.self, CheckStopCondMsg.init);
            send(ctx.self, GenSchema.init);
            ctx.state.isRunning = true;
        } catch (Exception e) {
            ctx.state.hasFatalError = true;
            logger.error(e.msg).collectException;
        }
    }

    static void generateSchema(ref Ctx ctx, GenSchema _) @trusted nothrow {
        try {
            ctx.state.activeSchema = typeof(ctx.state.activeSchema).init;
            ctx.state.injectIds = typeof(ctx.state.injectIds).init;

            ctx.self.request(ctx.state.genSchema, infTimeout)
                .send(GenSchema.init).capture(ctx).then((ref Ctx ctx, GenSchemaResult result) nothrow{
                if (result.noMoreScheman) {
                    ctx.state.isRunning = false;
                } else {
                    try {
                        send(ctx.self, RunSchema.init, result.schema, result.injectIds);
                    } catch (Exception e) {
                        ctx.state.isRunning = false;
                        logger.error(e.msg).collectException;
                    }
                }
            });
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    static void runSchema(ref Ctx ctx, RunSchema _, SchemataBuilder.ET schema,
            InjectIdResult injectIds) @safe nothrow {
        try {
            if (!ctx.state.borrow!((ref a) => a.isRunning)) {
                return;
            }
            if (ctx.state.borrow!((ref a) => schema.checksum.value in a.usedScheman)) {
                // discard, already used
                send(ctx.self, GenSchema.init);
                return;
            }

            ctx.state.borrow!((ref a) => a.usedScheman.add(schema.checksum.value));

            logger.trace("schema generated ", schema.checksum);
            logger.trace(schema.fragments.map!"a.file");
            logger.trace(schema.mutants);
            logger.trace(injectIds);

            if (injectIds.empty
                    || injectIds.length < ctx.state.borrow!(
                        (ref a) => a.conf.minMutantsPerSchema.get)) {
                send(ctx.self, GenSchema.init);
            } else {
                ctx.state.borrow!((ref a) => a.activeSchema = schema);
                ctx.state.borrow!((ref a) => a.injectIds = injectIds);
                send(ctx.self, InjectAndCompile.init);
            }
        } catch (Exception e) {
            logger.error(e.msg).collectException;
        }
    }

    static bool isDone(ref Ctx ctx, IsDone _) @safe {
        return ctx.state.borrow!((ref a) => !a.isRunning);
    }

    static void mark(ref Ctx ctx, MarkMsg _, FinalResult.Status status) @trusted nothrow {
        import dextool.plugin.mutate.backend.analyze.schema_ml : SchemaQ;

        static void updateSchemaQ(ref SchemaQ sq, ref SchemataBuilder.ET schema,
                const SchemaStatus status) @trusted nothrow {
            import my.hash : Checksum64;
            import my.set;

            auto paths = schema.fragments.map!"a.file".toSet.toRange.array;
            Set!Checksum64 latestFiles;

            foreach (path; paths) {
                scope getPath = (SchemaStatus s) {
                    return (s == status) ? schema.mutants.map!"a.mut.kind".toSet.toRange.array
                        : null;
                };
                try {
                    sq.update(path, getPath);
                } catch (Exception e) {
                    logger.warning(e.msg).collectException;
                }
                latestFiles.add(sq.pathCache[path]);
                debug logger.tracef("updating %s %s", path, sq.pathCache[path]);
            }

            // TODO: remove probability for non-existing files
            sq.scatterTick;
        }

        SchemaStatus schemaStatus = () {
            final switch (status) with (FinalResult.Status) {
            case fatalError:
                goto case;
            case invalidSchema:
                return SchemaStatus.broken;
            case noSchema:
                goto case;
            case ok:
                // TODO: remove SchemaStatus.allKilled
                return SchemaStatus.ok;
            }
        }();

        try {
            auto schemaQ = spinSql!(() => SchemaQ(ctx.db.schemaApi.getMutantProbability));
            ctx.state.borrow!((ref a) => updateSchemaQ(schemaQ, a.activeSchema, schemaStatus));
            ctx.state.borrow!((ref a) => send(a.dbSave, schemaQ));
            ctx.state.borrow!((ref a) => send(a.sizeQUpdater, SchemaGenStatusMsg.init,
                    schemaStatus, cast(long) a.activeSchema.mutants.length));
        } catch (Exception e) {
            logger.trace(e.msg).collectException;
        }
    }

    static void updateWlist(ref Ctx ctx, UpdateWorkList _, bool repeat) @safe nothrow {
        try {
            if (ctx.state.borrow!((ref a) => !a.isRunning))
                return;
            if (repeat)
                delayedSend(ctx.self, 1.dur!"minutes".delay, UpdateWorkList.init, true);

            ctx.state.borrow!((ref a) => a.whiteList = spinSql!(
                    () => ctx.db.worklistApi.getAll.map!"a.id".toSet));
            ctx.state.borrow!((ref a) => send(a.genSchema, a.whiteList.toArray));

            logger.trace("update schema worklist: ",
                    ctx.state.borrow!((ref a) => a.whiteList.length));
            debug logger.trace("update schema worklist: ",
                    ctx.state.borrow!((ref a) => a.whiteList.toRange));
        } catch (Exception e) {
            logger.trace(e.msg).collectException;
        }
    }

    static FinalResult doneStatus(ref Ctx ctx, GetDoneStatus _) @safe nothrow {
        try {
            FinalResult.Status status = () {
                if (ctx.state.borrow!((ref a) => a.hasFatalError))
                    return FinalResult.Status.fatalError;
                return FinalResult.Status.ok;
            }();
            return FinalResult(status, ctx.state.alive);
        } catch (Exception e) {
        }
        return FinalResult(FinalResult.Status.fatalError, 0);
    }

    static void save(ref Ctx ctx, SchemaTestResult data) @trusted {
        import dextool.plugin.mutate.backend.test_mutant.common_actors : GetMutantsLeft,
            UnknownMutantTested;

        void update(MutationTestResult a) {
            final switch (a.status) with (Mutation.Status) {
            case skipped:
                goto case;
            case unknown:
                goto case;
            case equivalent:
                goto case;
            case noCoverage:
                goto case;
            case alive:
                ctx.state.alive++;
                ctx.state.stopCheck.incrAliveMutants(1);
                return;
            case killed:
                goto case;
            case timeout:
                goto case;
            case memOverload:
                goto case;
            case killedByCompiler:
                break;
            }
        }

        debug logger.trace(data);

        if (!data.unstable.empty) {
            logger.warningf("Unstable test cases found: [%-(%s, %)]", data.unstable);
            logger.info(
                    "As configured the result is ignored which will force the mutant to be re-tested");
            return;
        }

        update(data.result);

        auto result = data.result;
        result.profile = MutantTimeProfile(ctx.state.compileTime, data.testTime);
        ctx.state.compileTime = Duration.zero;

        logger.infof("%s:%s (%s)", data.result.status,
                data.result.exitStatus.get, result.profile).collectException;
        logger.infof(!data.result.testCases.empty, `killed by [%-(%s, %)]`,
                data.result.testCases.sort.map!"a.name").collectException;

        send(ctx.state.dbSave, result, ctx.state.timeoutConf.iter);
        send(ctx.state.stat, UnknownMutantTested.init, 1L);

        // an error handler is required because the stat actor can be held up
        // for more than a minute.
        ctx.self.request(ctx.state.stat, delay(30.dur!"seconds"))
            .send(GetMutantsLeft.init).then((long x) {
            logger.infof("%s mutants left to test.", x);
        }, (ref Actor self, ErrorMsg) {});

        if (ctx.state.injectIds.empty && ctx.state.scheduler.full) {
            logger.trace("done saving result for schema ",
                    ctx.state.activeSchema.checksum).collectException;
            send(ctx.self, MarkMsg.init, FinalResult.Status.ok);
            send(ctx.self, UpdateWorkList.init, false);
            send(ctx.self, RestoreMsg.init).collectException;
        }
    }

    static void injectAndCompile(ref Ctx ctx, InjectAndCompile _) @safe nothrow {
        try {
            auto sw = StopWatch(AutoStart.yes);
            scope (exit)
                ctx.state.borrow!((ref a) => a.compileTime = sw.peek);

            ctx.state.borrow!((ref a) => logger.infof("Using schema with %s mutants",
                    a.injectIds.length));

            auto codeInject = () @trusted {
                return CodeInject(ctx.state.fio, ctx.state.conf);
            }();
            ctx.state.borrow!((ref a) => a.modifiedFiles = codeInject.inject(ctx.db,
                    a.activeSchema));
            codeInject.compile(ctx.state.borrow!((ref a) => a.buildCmd),
                    ctx.state.borrow!((ref a) => a.buildCmdTimeout));

            auto timeoutConf = ctx.state.borrow!((ref a) => a.timeoutConf);

            if (ctx.state.borrow!((ref a) => a.conf.sanityCheckSchemata)) {
                logger.info("Sanity check of the generated schemata");
                const sanity = ctx.state.borrow!((ref a) => sanityCheck(a.runner));
                if (sanity.isOk) {
                    if (ctx.state.borrow!((ref a) => a.timeoutConf.base) < sanity.runtime) {
                        timeoutConf.set(sanity.runtime);
                    }

                    logger.info("Ok".color(Color.green), ". Using test suite timeout ",
                            ctx.state.borrow!((ref a) => a.timeoutConf.value)).collectException;
                    send(ctx.self, StartTestMsg.init);
                } else {
                    logger.info("Skipping the schemata because the test suite failed".color(Color.yellow)
                            .toString);
                    send(ctx.self, MarkMsg.init, FinalResult.Status.invalidSchema);
                    send(ctx.self, RestoreMsg.init).collectException;
                }
            } else {
                send(ctx.self, StartTestMsg.init);
            }
            ctx.state.borrow!((ref a) => a.scheduler.configure(timeoutConf));
        } catch (Exception e) {
            send(ctx.self, MarkMsg.init, FinalResult.Status.invalidSchema).collectException;
            send(ctx.self, RestoreMsg.init).collectException;
            logger.warning(e.msg).collectException;
        }
    }

    static void restore(ref Ctx ctx, RestoreMsg _) @safe nothrow {
        import dextool.plugin.mutate.backend.test_mutant.common : restoreFiles;

        try {
            ctx.state.borrow!((ref a) => logger.trace("restore ", a.modifiedFiles));
            ctx.state.borrow!((ref a) => restoreFiles(a.modifiedFiles, a.fio));
            ctx.state.borrow!((ref a) => a.modifiedFiles = null);
            send(ctx.self, GenSchema.init);
        } catch (Exception e) {
            ctx.state.borrow!((ref a) => a.hasFatalError = true).collectException;
            ctx.state.borrow!((ref a) => a.isRunning = false).collectException;
            logger.error(e.msg).collectException;
        }
    }

    static void startTest(ref Ctx ctx, StartTestMsg _) @safe nothrow {
        try {
            ctx.state.borrow!(
                    (ref a) => a.activeSchemaCheck = State.ActiveSchemaCheck.noMutantTested);
            foreach (_0; 0 .. ctx.state.borrow!((ref a) => a.scheduler.testers.length))
                send(ctx.self, ScheduleTestMsg.init);
            ctx.state.borrow!((ref a) => logger.tracef("sent %s ScheduleTestMsg",
                    a.scheduler.testers.length));
        } catch (Exception e) {
            ctx.state.borrow!((ref a) => a.hasFatalError = true).collectException;
            ctx.state.borrow!((ref a) => a.isRunning = false).collectException;
            logger.error(e.msg).collectException;
        }
    }

    static void test(ref Ctx ctx, ScheduleTestMsg _) @safe nothrow {
        // TODO: move this printer to another thread because it perform
        // significant DB lookup and can potentially slow down the testing.
        void print(MutationStatusId statusId) @trusted {
            import dextool.plugin.mutate.backend.generate_mutant : makeMutationText;

            auto entry_ = spinSql!(() => ctx.db.mutantApi.getMutation(statusId));
            if (entry_.isNull)
                return;
            auto entry = entry_.get;

            try {
                const file = ctx.state.borrow!((ref a) => a.fio.toAbsoluteRoot(entry.file));
                auto txt = makeMutationText(ctx.state.borrow!((ref a) => a.fio.makeInput(file)),
                        entry.mp.offset, entry.mp.mutations[0].kind, entry.lang);
                debug logger.trace(entry);
                logger.infof("from '%s' to '%s' in %s:%s:%s", txt.original,
                        txt.mutation, file, entry.sloc.line, entry.sloc.column);
            } catch (Exception e) {
                logger.info(e.msg).collectException;
            }
        }

        try {
            if (ctx.state.borrow!((ref a) => !a.isRunning))
                return;
        } catch (Exception e) {
            return;
        }

        try {
            if (ctx.state.borrow!((ref a) => a.injectIds.empty)) {
                logger.trace("no mutants left to test ",
                        ctx.state.borrow!((ref a) => a.scheduler.free.length));
                if (ctx.state.borrow!((ref a) => a.activeSchemaCheck == State.ActiveSchemaCheck.noMutantTested
                        && a.scheduler.full)) {
                    // no mutant has been tested in the schema thus the restore in save is never triggered.
                    send(ctx.self, RestoreMsg.init);
                    ctx.state.borrow!(
                            (ref a) => a.activeSchemaCheck
                            = State.ActiveSchemaCheck.triggerRestoreOnce);
                }
                return;
            }

            if (ctx.state.borrow!((ref a) => a.scheduler.empty)) {
                logger.trace("no free worker");
                delayedSend(ctx.self, 1.dur!"seconds".delay, ScheduleTestMsg.init);
                return;
            }

            if (ctx.state.borrow!((ref a) => a.stopCheck.isOverloaded)) {
                logger.info(ctx.state.borrow!((ref a) => a.stopCheck.overloadToString))
                    .collectException;
                delayedSend(ctx.self, 30.dur!"seconds".delay, ScheduleTestMsg.init);
                return;
            }

            auto m = ctx.state.borrow!((ref a) => a.injectIds.front);
            ctx.state.borrow!((ref a) => a.injectIds.popFront);

            if (ctx.state.borrow!((ref a) => m.statusId in a.whiteList)) {
                ctx.state.borrow!((ref a) => a.activeSchemaCheck = State.ActiveSchemaCheck.testing);
                auto testerId = ctx.state.borrow!((ref a) => a.scheduler.pop);
                auto tester = ctx.state.borrow!((ref a) => a.scheduler.get(testerId));
                print(m.statusId);
                () @trusted {
                    ctx.self.request(tester, infTimeout).send(m).capture(ctx,
                            testerId).then((ref Capture!(Ctx, size_t) ctx, SchemaTestResult x) {
                        ctx[0].state.scheduler.put(ctx[1]);
                        send(ctx[0].self, x);
                        send(ctx[0].self, ScheduleTestMsg.init);
                    });
                }();
            } else {
                debug logger.tracef("%s not in whitelist. Skipping", m);
                send(ctx.self, ScheduleTestMsg.init);
            }
        } catch (Exception e) {
            ctx.state.borrow!((ref a) => a.hasFatalError = true).collectException;
            ctx.state.borrow!((ref a) => a.isRunning = false).collectException;
            logger.error(e.msg).collectException;
        }
    }

    static void checkHaltCond(ref Ctx ctx, CheckStopCondMsg _) @safe nothrow {
        try {
            if (ctx.state.borrow!((ref a) => !a.isRunning))
                return;

            delayedSend(ctx.self, 5.dur!"seconds".delay, CheckStopCondMsg.init).collectException;

            const halt = ctx.state.borrow!((ref a) => a.stopCheck.isHalt);
            if (halt == TestStopCheck.HaltReason.overloaded)
                ctx.state.borrow!((ref a) => a.stopCheck.startBgShutdown);

            if (halt != TestStopCheck.HaltReason.none) {
                send(ctx.self, RestoreMsg.init);
                send(ctx.self, Stop.init);
                logger.info(ctx.state.borrow!((ref a) => a.stopCheck.overloadToString));
            }
        } catch (Exception e) {
            ctx.state.borrow!((ref a) => a.isRunning = false).collectException;
            logger.error(e.msg).collectException;
        }
    }

    static void stop(ref Ctx ctx, Stop _) @trusted nothrow {
        ctx.state.isRunning = false;
    }

    import std.functional : toDelegate;

    self.name = "schemaDriver";
    self.exceptionHandler = toDelegate(&logExceptionHandler);
    try {
        send(self, Init.init, dbPath, buildCmd, buildCmdTimeout);
    } catch (Exception e) {
        logger.error(e.msg).collectException;
        self.shutdown;
    }

    return impl(self, st, &init_, &isDone, &updateWlist, &doneStatus,
            &save, &mark, &injectAndCompile, &restore, &startTest, &test,
            &checkHaltCond, &generateSchema, &runSchema, &stop);
}

private SchemaSizeQ getSchemaSizeQ(ref Database db, const long userInit, const long minSize) @trusted nothrow {
    // 1.1 is a magic number. it feels good. the purpose is to be a little
    // leniant with the size to demonstrate to the user that it is OK to
    // raise the max size. At the same time it shouldn't be too much
    // because the user may have configured it to a low value for a reason.
    auto sq = SchemaSizeQ.make(minSize, cast(long)(userInit * 1.1));
    sq.updateSize(spinSql!(() => db.schemaApi.getSchemaSize(userInit)));
    sq.testMutantsSize = spinSql!(() => db.worklistApi.getCount);
    return sq;
}

private {
    struct GenSchemaResult {
        bool noMoreScheman;
        SchemataBuilder.ET schema;
        InjectIdResult injectIds;
    }
}

// dfmt off
alias GenSchemaActor = typedActor!(
    void function(Init, AbsolutePath database, ConfigSchema conf),
    GenSchemaResult function(GenSchema),
    void function(MutationStatusId[] whiteList),
    );
// dfmt on

private auto spawnGenSchema(GenSchemaActor.Impl self, AbsolutePath dbPath,
        ConfigSchema conf, SchemaSizeQUpdateActor.Address sizeQUpdater) @trusted {
    static struct State {
        ConfigSchema conf;
        SchemaSizeQUpdateActor.Address sizeQUpdater;
        SchemaBuildState schemaBuild;
        Set!MutationStatusId whiteList;
        // never use fragments that contain a mutant in this list.
        Set!MutationStatusId denyList;
    }

    auto st = tuple!("self", "state", "db")(self, refCounted(State(conf,
            sizeQUpdater)), Database.init);
    alias Ctx = typeof(st);

    static void init_(ref Ctx ctx, Init _, AbsolutePath dbPath, ConfigSchema conf) nothrow {
        import dextool.plugin.mutate.backend.database : dbOpenTimeout;

        try {
            ctx.db = spinSql!(() => Database.make(dbPath), logger.trace)(dbOpenTimeout);

            ctx.state.denyList = spinSql!(() => ctx.db.mutantApi.getAllMutationStatus(
                    Mutation.Status.killedByCompiler)).toSet;

            ctx.state.schemaBuild.minMutantsPerSchema = ctx.state.conf.minMutantsPerSchema;
            ctx.state.schemaBuild.mutantsPerSchema.get = ctx.state.conf.mutantsPerSchema.get;
            ctx.state.schemaBuild.initFiles(spinSql!(() => ctx.db.fileApi.getFileIds));
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            // TODO: should terminate?
        }
    }

    static void updateWhiteList(ref Ctx ctx, MutationStatusId[] whiteList) @trusted nothrow {
        try {
            ctx.state.whiteList = whiteList.toSet;
            send(ctx.state.sizeQUpdater, MutantsToTestMsg.init,
                    cast(long) ctx.state.whiteList.length);

            ctx.state.schemaBuild.builder.schemaQ = spinSql!(
                    () => SchemaQ(ctx.db.schemaApi.getMutantProbability));

            ctx.self.request(ctx.state.sizeQUpdater, infTimeout)
                .send(GetSchemaSizeMsg.init).capture(ctx).then((ref Ctx ctx, long sz) nothrow{
                ctx.state.schemaBuild.mutantsPerSchema.get = sz;
            });
        } catch (Exception e) {
        }
    }

    static GenSchemaResult genSchema(ref Ctx ctx, GenSchema _) nothrow {
        static void process(ref Ctx ctx, ref GenSchemaResult result,
                ref Set!MutationStatusId whiteList) @safe {
            auto value = ctx.state.borrow!((ref a) => a.schemaBuild.process);
            value.match!((Some!(SchemataBuilder.ET) a) {
                result.schema = a;
                result.injectIds = mutantsFromSchema(a, whiteList);
            }, (None a) {});
        }

        static void processFile(ref Ctx ctx, ref Set!MutationStatusId whiteList,
                ref Set!MutationStatusId denyList) @trusted nothrow {
            if (ctx.state.schemaBuild.files.isDone)
                return;

            size_t frags;
            while (frags == 0 && ctx.state.schemaBuild.files.filesLeft != 0) {
                logger.trace("Files left ", ctx.state.schemaBuild.files.filesLeft).collectException;
                frags = spinSql!(() {
                    auto trans = ctx.db.transaction;
                    return ctx.state.schemaBuild.updateFiles(whiteList, denyList,
                        (FileId id) => spinSql!(() => ctx.db.schemaApi.getFragments(id)),
                        (FileId id) => spinSql!(() => ctx.db.getFile(id)),
                        (MutationStatusId id) => spinSql!(() => ctx.db.mutantApi.getKind(id)));
                });
                logger.trace("Files left foo").collectException;
            }
        }

        GenSchemaResult result;

        logger.trace("Generate schema").collectException;
        while (ctx.state.schemaBuild.st != SchemaBuildState.State.done) {
            ctx.state.schemaBuild.tick;

            final switch (ctx.state.schemaBuild.st) {
            case SchemaBuildState.State.none:
                break;
            case SchemaBuildState.State.processFiles:
                try {
                    processFile(ctx, ctx.state.whiteList, ctx.state.denyList);
                    process(ctx, result, ctx.state.whiteList);
                } catch (Exception e) {
                    logger.trace(e.msg).collectException;
                    return GenSchemaResult(true);
                }
                break;
            case SchemaBuildState.State.prepareReduction:
                send(ctx.state.sizeQUpdater,
                        FullSchemaGenDoneMsg.init).collectException;
                goto case;
            case SchemaBuildState.State.prepareFinalize:
                try {
                    ctx.state.schemaBuild.files.reset;
                } catch (Exception e) {
                    logger.trace(e.msg).collectException;
                    return GenSchemaResult(true);
                }
                break;
            case SchemaBuildState.State.reduction:
                goto case;
            case SchemaBuildState.State.finalize1:
                goto case;
            case SchemaBuildState.State.finalize2:
                try {
                    processFile(ctx, ctx.state.whiteList, ctx.state.denyList);
                    process(ctx, result, ctx.state.whiteList);
                } catch (Exception e) {
                    logger.trace(e.msg).collectException;
                    return GenSchemaResult(true);
                }
                break;
            case SchemaBuildState.State.done:
                ctx.state.schemaBuild.files.clear;
                return GenSchemaResult(true);
            }

            if (!result.injectIds.empty)
                return result;
        }

        return GenSchemaResult(true);
    }

    self.name = "generateSchema";

    try {
        send(self, Init.init, dbPath, conf);
    } catch (Exception e) {
        logger.error(e.msg).collectException;
        self.shutdown;
    }

    return impl(self, st, &init_, &genSchema, &updateWhiteList);
}

private {
    struct FullSchemaGenDoneMsg {
    }

    struct MutantsToTestMsg {
    }

    struct SchemaGenStatusMsg {
    }

    struct GetSchemaSizeMsg {
    }

    struct SaveSizeQMsg {
    }
}

// dfmt off
alias SchemaSizeQUpdateActor = typedActor!(
    // Signal that no more full scheman are generated.
    void function(FullSchemaGenDoneMsg),
    // mutants to test when the scheman where generated
    void function(MutantsToTestMsg, long number),
    // if the generation where successfull
    void function(SchemaGenStatusMsg, SchemaStatus, long mutantsInSchema),
    /// The currently state of the size to use for scheman.
    long function(GetSchemaSizeMsg),
    );
// dfmt on

private auto spawnSchemaSizeQ(SchemaSizeQUpdateActor.Impl self,
        SchemaSizeQ sizeQ, DbSaveActor.Address dbSave) @trusted {
    static struct State {
        DbSaveActor.Address dbSave;
        // state of the sizeq algorithm.
        SchemaSizeQ sizeQ;
        // number of scheman that has been generated.
        long genCount;
    }

    auto st = tuple!("self", "state")(self, refCounted(State(dbSave, sizeQ)));
    alias Ctx = typeof(st);

    static void updateMutantsNumber(ref Ctx ctx, MutantsToTestMsg _, long number) @safe {
        ctx.state.borrow!((ref a) => a.sizeQ.testMutantsSize = number);
    }

    static void genStatus(ref Ctx ctx, SchemaGenStatusMsg,
            SchemaStatus status, long mutantsInSchema) @safe nothrow {
        ctx.state.borrow!((ref a) => a.genCount++);
        try {
            ctx.state.borrow!((ref a) => a.sizeQ.update(status, mutantsInSchema));
            ctx.state.borrow!((ref a) => send(a.dbSave, a.sizeQ));
            ctx.state.borrow!((ref a) @trusted { logger.trace(a.sizeQ); });
        } catch (Exception e) {
            logger.info(e.msg).collectException;
        }
    }

    static void fullGenDone(ref Ctx ctx, FullSchemaGenDoneMsg _) @safe nothrow {
        if (ctx.state.borrow!((ref a) => a.genCount) == 0) {
            try {
                ctx.state.borrow!((ref a) => a.sizeQ.noCurrentSize);
                ctx.state.borrow!((ref a) => send(a.dbSave, a.sizeQ));
                ctx.state.borrow!((ref a) { logger.trace(a.sizeQ); });
            } catch (Exception e) {
                logger.info(e.msg).collectException;
            }
        }
    }

    static long getSize(ref Ctx ctx, GetSchemaSizeMsg _) @safe nothrow {
        return ctx.state.borrow!((ref a) => a.sizeQ.currentSize);
    }

    self.name = "schemaSizeQUpdater";

    return impl(self, st, &updateMutantsNumber, &getSize, &genStatus, &fullGenDone);
}

/** Generate schemata injection IDs (32bit) from mutant checksums (128bit).
 *
 * There is a possibility that an injection ID result in a collision because
 * they are only 32 bit. If that happens the mutant is discarded as unfeasable
 * to use for schemata.
 *
 * TODO: if this is changed to being order dependent then it can handle all
 * mutants. But I can't see how that can be done easily both because of how the
 * schemas are generated and how the database is setup.
 */
struct InjectIdBuilder {
    private {
        alias InjectId = InjectIdResult.InjectId;

        InjectId[uint] result;
        Set!uint collisions;
    }

    void put(MutationStatusId id, Checksum cs) @safe pure nothrow {
        import dextool.plugin.mutate.backend.analyze.pass_schemata : checksumToId;

        const injectId = checksumToId(cs);
        debug logger.tracef("%s %s %s", id, cs, injectId).collectException;

        if (injectId in collisions) {
        } else if (injectId in result) {
            collisions.add(injectId);
            result.remove(injectId);
        } else {
            result[injectId] = InjectId(id, injectId);
        }
    }

    InjectIdResult finalize() @safe nothrow {
        import std.array : array;
        import std.random : randomCover;

        return InjectIdResult(result.byValue.array.randomCover.array);
    }
}

struct InjectIdResult {
    struct InjectId {
        MutationStatusId statusId;
        uint injectId;
    }

    InjectId[] ids;

    InjectId front() @safe pure nothrow {
        assert(!empty, "Can't get front of an empty range");
        return ids[0];
    }

    void popFront() @safe pure nothrow {
        assert(!empty, "Can't pop front of an empty range");
        ids = ids[1 .. $];
    }

    bool empty() @safe pure nothrow const @nogc {
        return ids.empty;
    }

    size_t length() @safe pure nothrow const @nogc scope {
        return ids.length;
    }
}

/// Extract the mutants that are part of the schema.
InjectIdResult mutantsFromSchema(ref SchemataBuilder.ET schema, ref Set!MutationStatusId whiteList) {
    import dextool.plugin.mutate.backend.database.type : toMutationStatusId;

    InjectIdBuilder builder;
    foreach (mutant; schema.mutants.filter!(a => a.id.toMutationStatusId in whiteList)) {
        builder.put(mutant.id.toMutationStatusId, mutant.id);
    }

    return builder.finalize;
}

@("shall detect a collision and make sure it is never part of the result")
unittest {
    InjectIdBuilder builder;
    builder.put(MutationStatusId(1), Checksum(1));
    builder.put(MutationStatusId(2), Checksum(2));
    builder.put(MutationStatusId(3), Checksum(1));
    auto r = builder.finalize;

    assert(r.front.statusId == MutationStatusId(2));
    r.popFront;
    assert(r.empty);
}

Edit[] makeRootImpl(ulong end) {
    import dextool.plugin.mutate.backend.resource : schemataImpl;

    return [
        makeHdr[0], new Edit(Interval(end, end), cast(const(ubyte)[]) schemataImpl)
    ];
}

Edit[] makeHdr() {
    import dextool.plugin.mutate.backend.resource : schemataHeader;

    return [new Edit(Interval(0, 0), cast(const(ubyte)[]) schemataHeader)];
}

/** Injects the schema and runtime.
 *
 * Uses exceptions to signal failure.
 */
struct CodeInject {
    FilesysIO fio;

    Set!AbsolutePath roots;

    /// Unique checksum for the schema.
    Checksum checksum;

    bool logSchema;

    this(FilesysIO fio, ConfigSchema conf) {
        this.fio = fio;
        this.logSchema = conf.log;

        foreach (a; conf.userRuntimeCtrl) {
            auto p = fio.toAbsoluteRoot(a.file);
            roots.add(p);
        }
    }

    /// Throws an error on failure.
    /// Returns: modified files.
    AbsolutePath[] inject(ref Database db, SchemataBuilder.ET schemata) {
        checksum = schemata.checksum.value;
        auto modifiedFiles = schemata.fragments.map!(a => fio.toAbsoluteRoot(a.file))
            .toSet.toRange.array;

        void initRoots(ref Database db) {
            if (roots.empty) {
                auto allRoots = () {
                    AbsolutePath[] tmp;
                    try {
                        tmp = spinSql!(() => db.getRootFiles.map!(a => db.getFile(a).get)).map!(
                                a => fio.toAbsoluteRoot(a)).array;
                        if (tmp.empty) {
                            // no root found. Inject the runtime in all files and "hope for
                            // the best". it will be less efficient but the weak symbol
                            // should still mean that it link correctly.
                            tmp = modifiedFiles;
                        }
                    } catch (Exception e) {
                        logger.error(e.msg).collectException;
                    }
                    return tmp;
                }();

                foreach (r; allRoots) {
                    roots.add(r);
                }
            }

            auto mods = modifiedFiles.toSet;
            foreach (r; roots.toRange) {
                if (r !in mods)
                    modifiedFiles ~= r;
            }

            if (roots.empty)
                throw new Exception("No root file found to inject the schemata runtime in");
        }

        void injectCode() {
            import std.path : extension, stripExtension;

            alias SchemataFragment = SchemataBuilder.SchemataFragment;

            Blob makeSchemata(Blob original, SchemataFragment[] fragments, Edit[] extra) {
                auto edits = appender!(Edit[])();
                edits.put(extra);
                foreach (a; fragments) {
                    edits ~= new Edit(Interval(a.offset.begin, a.offset.end), a.text);
                }
                auto m = merge(original, edits.data);
                return change(new Blob(original.uri, original.content), m.edits);
            }

            SchemataFragment[] fragments(Path p) {
                return schemata.fragments.filter!(a => a.file == p).array;
            }

            foreach (fname; modifiedFiles) {
                auto f = fio.makeInput(fname);
                auto extra = () {
                    if (fname in roots) {
                        logger.trace("Injecting schemata runtime in ", fname);
                        return makeRootImpl(f.content.length);
                    }
                    return makeHdr;
                }();

                // writing the schemata.
                auto frags = fragments(fio.toRelativeRoot(fname));
                auto s = makeSchemata(f, frags, extra);
                fio.makeOutput(fname).write(s);
                if (!frags.empty) {
                    logger.infof("Injecting schema of size %s in %s",
                            frags.map!"a.text.length".sum, fname);
                }

                if (logSchema) {
                    const ext = fname.toString.extension;
                    fio.makeOutput(AbsolutePath(format!"%s.%s.schema%s"(fname.toString.stripExtension,
                            checksum.c0, ext).Path)).write(s);
                }
            }
        }

        initRoots(db);
        injectCode;

        return modifiedFiles;
    }

    void compile(ShellCommand buildCmd, Duration buildCmdTimeout) {
        import dextool.plugin.mutate.backend.test_mutant.common : compile;

        logger.infof("Compile schema %s", checksum.c0).collectException;

        compile(buildCmd, buildCmdTimeout, PrintCompileOnFailure(true)).match!((Mutation.Status a) {
            throw new Exception("Skipping schema because it failed to compile".color(Color.yellow)
                .toString);
        }, (bool success) {
            if (!success) {
                throw new Exception("Skipping schema because it failed to compile".color(Color.yellow)
                    .toString);
            }
        });

        logger.info("Ok".color(Color.green)).collectException;
    }
}

// Check that the test suite successfully execute "passed".
// Returns: true on success.
Tuple!(bool, "isOk", Duration, "runtime") sanityCheck(ref TestRunner runner) {
    auto sw = StopWatch(AutoStart.yes);
    auto res = runner.run;
    return typeof(return)(res.status == TestResult.Status.passed, sw.peek);
}

/// Language generic schemata result.
class SchemataResult {
    static struct Fragment {
        Offset offset;
        const(ubyte)[] text;
        CodeMutant[] mutants;
    }

    static struct Fragments {
        // TODO: change to using appender
        Fragment[] fragments;
    }

    private {
        Fragments[AbsolutePath] fragments;
    }

    /// Returns: all fragments containing mutants per file.
    Fragments[AbsolutePath] getFragments() @safe {
        return fragments;
    }

    /// Assuming that all fragments for a file should be merged to one huge.
    private void putFragment(AbsolutePath file, Fragment sf) {
        fragments.update(file, () => Fragments([sf]), (ref Fragments a) {
            a.fragments ~= sf;
        });
    }

    override string toString() @safe {
        import std.range : put;
        import std.utf : byUTF;

        auto w = appender!string();

        void toBuf(Fragments s) {
            foreach (f; s.fragments) {
                formattedWrite(w, "  %s: %s\n", f.offset,
                        (cast(const(char)[]) f.text).byUTF!(const(char)));
                formattedWrite(w, "%(    %s\n%)\n", f.mutants);
            }
        }

        foreach (k; fragments.byKey.array.sort) {
            try {
                formattedWrite(w, "%s:\n", k);
                toBuf(fragments[k]);
            } catch (Exception e) {
            }
        }

        return w.data;
    }
}
