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
import std.algorithm : sort, map, filter, among;
import std.array : empty, array, appender;
import std.conv : to;
import std.datetime : Duration, dur, Clock, SysTime;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.exception : collectException;
import std.format : format;
import std.typecons : Tuple, tuple, Nullable;
import std.sumtype;

import blob_model;
import colorlog;
import miniorm : spinSql, silentLog;
import my.actor;
import my.gc.refc;
import my.optional;
import my.container.vector;
import proc : DrainElement;

import my.path;
import my.set;

import dextool.plugin.mutate.backend.database : MutationStatusId, Database,
    spinSql, SchemataId, Schemata, FileId;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.analyze.schema_ml : SchemaQ, SchemaSizeQ, SchemaStatus;
import dextool.plugin.mutate.backend.test_mutant.common;
import dextool.plugin.mutate.backend.test_mutant.common_actors : DbSaveActor, StatActor;
import dextool.plugin.mutate.backend.test_mutant.test_cmd_runner : TestRunner, TestResult;
import dextool.plugin.mutate.backend.test_mutant.timeout : TimeoutFsm, TimeoutConfig;
import dextool.plugin.mutate.backend.type : Mutation, TestCase, Checksum;
import dextool.plugin.mutate.type : TestCaseAnalyzeBuiltin, ShellCommand,
    UserRuntime, SchemaRuntime;
import dextool.plugin.mutate.config : ConfigSchema;

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

        Database db;

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

    auto st = tuple!("self", "state")(self, refCounted(State(stopCheck, dbSave,
            stat, timeoutConf, fio.dup, runner.dup, testCaseAnalyzer, conf)));
    alias Ctx = typeof(st);

    static void init_(ref Ctx ctx, Init _, AbsolutePath dbPath,
            ShellCommand buildCmd, Duration buildCmdTimeout) nothrow {
        import dextool.plugin.mutate.backend.database : dbOpenTimeout;

        try {
            ctx.state.get.db = spinSql!(() => Database.make(dbPath), logger.trace)(dbOpenTimeout);
            ctx.state.get.buildCmd = buildCmd;
            ctx.state.get.buildCmdTimeout = buildCmdTimeout;

            ctx.state.get.timeoutConf.timeoutScaleFactor = ctx.state.get.conf.timeoutScaleFactor;
            logger.tracef("Timeout Scale Factor: %s", ctx.state.get.timeoutConf.timeoutScaleFactor);
            ctx.state.get.runner.timeout = ctx.state.get.timeoutConf.value;

            ctx.state.get.scheduler = () {
                TestMutantActor.Address[] testers;
                foreach (_0; 0 .. ctx.state.get.conf.parallelMutants) {
                    auto a = ctx.self.homeSystem.spawn(&spawnTestMutant,
                            ctx.state.get.runner.dup, ctx.state.get.analyzer);
                    a.linkTo(ctx.self.address);
                    testers ~= a;
                }
                return ScheduleTest(testers);
            }();

            ctx.state.get.sizeQUpdater = ctx.self.homeSystem.spawn(&spawnSchemaSizeQ,
                    getSchemaSizeQ(ctx.state.get.db, ctx.state.get.conf.mutantsPerSchema.get,
                        ctx.state.get.conf.minMutantsPerSchema.get), ctx.state.get.dbSave);
            linkTo(ctx.self, ctx.state.get.sizeQUpdater);

            ctx.state.get.genSchema = ctx.self.homeSystem.spawn(&spawnGenSchema,
                    dbPath, ctx.state.get.conf, ctx.state.get.sizeQUpdater);
            linkTo(ctx.self, ctx.state.get.genSchema);

            send(ctx.self, UpdateWorkList.init, true);
            send(ctx.self, CheckStopCondMsg.init);
            send(ctx.self, GenSchema.init);
            ctx.state.get.isRunning = true;
        } catch (Exception e) {
            ctx.state.get.hasFatalError = true;
            logger.error(e.msg).collectException;
        }
    }

    static void generateSchema(ref Ctx ctx, GenSchema _) @trusted nothrow {
        try {
            ctx.state.get.activeSchema = typeof(ctx.state.get.activeSchema).init;
            ctx.state.get.injectIds = typeof(ctx.state.get.injectIds).init;

            ctx.self.request(ctx.state.get.genSchema, infTimeout)
                .send(GenSchema.init).capture(ctx).then((ref Ctx ctx, GenSchemaResult result) nothrow{
                if (result.noMoreScheman) {
                    ctx.state.get.isRunning = false;
                } else {
                    try {
                        send(ctx.self, RunSchema.init, result.schema, result.injectIds);
                    } catch (Exception e) {
                        ctx.state.get.isRunning = false;
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
            if (!ctx.state.get.isRunning) {
                return;
            }
            if (schema.checksum.value in ctx.state.get.usedScheman) {
                // discard, already used
                send(ctx.self, GenSchema.init);
                return;
            }

            ctx.state.get.usedScheman.add(schema.checksum.value);

            logger.trace("schema generated ", schema.checksum);
            logger.trace(schema.fragments.map!"a.file");
            logger.trace(schema.mutants);
            logger.trace(injectIds);

            if (injectIds.empty || injectIds.length < ctx.state.get.conf.minMutantsPerSchema.get) {
                send(ctx.self, GenSchema.init);
            } else {
                ctx.state.get.activeSchema = schema;
                ctx.state.get.injectIds = injectIds;
                send(ctx.self, InjectAndCompile.init);
            }
        } catch (Exception e) {
            logger.error(e.msg).collectException;
        }
    }

    static bool isDone(ref Ctx ctx, IsDone _) {
        return !ctx.state.get.isRunning;
    }

    static void mark(ref Ctx ctx, MarkMsg _, FinalResult.Status status) @safe nothrow {
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

            // TODO: remove prob for non-existing files
            sq.scatterTick;
        }

        SchemaStatus schemaStatus = () {
            final switch (status) with (FinalResult.Status) {
            case fatalError:
                goto case;
            case invalidSchema:
                return SchemaStatus.broken;
            case ok:
                // TODO: remove SchemaStatus.allKilled
                return SchemaStatus.ok;
            }
        }();

        try {
            auto schemaQ = spinSql!(() => SchemaQ(ctx.state.get.db.schemaApi.getMutantProbability));
            updateSchemaQ(schemaQ, ctx.state.get.activeSchema, schemaStatus);
            send(ctx.state.get.dbSave, schemaQ);

            send(ctx.state.get.sizeQUpdater, SchemaGenStatusMsg.init,
                    schemaStatus, cast(long) ctx.state.get.activeSchema.mutants.length);
        } catch (Exception e) {
            logger.trace(e.msg).collectException;
        }
    }

    static void updateWlist(ref Ctx ctx, UpdateWorkList _, bool repeat) @safe nothrow {
        if (!ctx.state.get.isRunning)
            return;

        try {
            if (repeat)
                delayedSend(ctx.self, 1.dur!"minutes".delay, UpdateWorkList.init, true);

            ctx.state.get.whiteList = spinSql!(() => ctx.state.get.db.worklistApi.getAll)
                .map!"a.id".toSet;
            send(ctx.state.get.genSchema, ctx.state.get.whiteList.toArray);

            logger.trace("update schema worklist: ", ctx.state.get.whiteList.length);
            debug logger.trace("update schema worklist: ", ctx.state.get.whiteList.toRange);
        } catch (Exception e) {
            logger.trace(e.msg).collectException;
        }
    }

    static FinalResult doneStatus(ref Ctx ctx, GetDoneStatus _) @safe nothrow {
        FinalResult.Status status = () {
            if (ctx.state.get.hasFatalError)
                return FinalResult.Status.fatalError;
            return FinalResult.Status.ok;
        }();

        return FinalResult(status, ctx.state.get.alive);
    }

    static void save(ref Ctx ctx, SchemaTestResult data) {
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
                ctx.state.get.alive++;
                ctx.state.get.stopCheck.incrAliveMutants(1);
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
        result.profile = MutantTimeProfile(ctx.state.get.compileTime, data.testTime);
        ctx.state.get.compileTime = Duration.zero;

        logger.infof("%s:%s (%s)", data.result.status,
                data.result.exitStatus.get, result.profile).collectException;
        logger.infof(!data.result.testCases.empty, `killed by [%-(%s, %)]`,
                data.result.testCases.sort.map!"a.name").collectException;

        send(ctx.state.get.dbSave, result, ctx.state.get.timeoutConf.iter);
        send(ctx.state.get.stat, UnknownMutantTested.init, 1L);

        // an error handler is required because the stat actor can be held up
        // for more than a minute.
        ctx.self.request(ctx.state.get.stat, delay(5.dur!"seconds"))
            .send(GetMutantsLeft.init).then((long x) {
            logger.infof("%s mutants left to test.", x);
        }, (ref Actor self, ErrorMsg) {});

        if (ctx.state.get.injectIds.empty && ctx.state.get.scheduler.full) {
            logger.trace("done saving result for schema ",
                    ctx.state.get.activeSchema.checksum).collectException;
            send(ctx.self, MarkMsg.init, FinalResult.Status.ok);
            send(ctx.self, UpdateWorkList.init, false);
            send(ctx.self, RestoreMsg.init).collectException;
        }
    }

    static void injectAndCompile(ref Ctx ctx, InjectAndCompile _) @safe nothrow {
        try {
            auto sw = StopWatch(AutoStart.yes);
            scope (exit)
                ctx.state.get.compileTime = sw.peek;

            logger.infof("Using schema with %s mutants", ctx.state.get.injectIds.length);

            auto codeInject = CodeInject(ctx.state.get.fio, ctx.state.get.conf);
            ctx.state.get.modifiedFiles = codeInject.inject(ctx.state.get.db,
                    ctx.state.get.activeSchema);
            codeInject.compile(ctx.state.get.buildCmd, ctx.state.get.buildCmdTimeout);

            auto timeoutConf = ctx.state.get.timeoutConf;

            if (ctx.state.get.conf.sanityCheckSchemata) {
                logger.info("Sanity check of the generated schemata");
                const sanity = sanityCheck(ctx.state.get.runner);
                if (sanity.isOk) {
                    if (ctx.state.get.timeoutConf.base < sanity.runtime) {
                        timeoutConf.set(sanity.runtime);
                    }

                    logger.info("Ok".color(Color.green), ". Using test suite timeout ",
                            ctx.state.get.timeoutConf.value).collectException;
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
            ctx.state.get.scheduler.configure(timeoutConf);
        } catch (Exception e) {
            send(ctx.self, MarkMsg.init, FinalResult.Status.invalidSchema).collectException;
            send(ctx.self, RestoreMsg.init).collectException;
            logger.warning(e.msg).collectException;
        }
    }

    static void restore(ref Ctx ctx, RestoreMsg _) @safe nothrow {
        import dextool.plugin.mutate.backend.test_mutant.common : restoreFiles;

        try {
            logger.trace("restore ", ctx.state.get.modifiedFiles);
            restoreFiles(ctx.state.get.modifiedFiles, ctx.state.get.fio);
            ctx.state.get.modifiedFiles = null;
            send(ctx.self, GenSchema.init);
        } catch (Exception e) {
            ctx.state.get.hasFatalError = true;
            ctx.state.get.isRunning = false;
            logger.error(e.msg).collectException;
        }
    }

    static void startTest(ref Ctx ctx, StartTestMsg _) @safe nothrow {
        ctx.state.get.activeSchemaCheck = State.ActiveSchemaCheck.noMutantTested;

        try {
            foreach (_0; 0 .. ctx.state.get.scheduler.testers.length)
                send(ctx.self, ScheduleTestMsg.init);
            logger.tracef("sent %s ScheduleTestMsg", ctx.state.get.scheduler.testers.length);
        } catch (Exception e) {
            ctx.state.get.hasFatalError = true;
            ctx.state.get.isRunning = false;
            logger.error(e.msg).collectException;
        }
    }

    static void test(ref Ctx ctx, ScheduleTestMsg _) nothrow {
        // TODO: move this printer to another thread because it perform
        // significant DB lookup and can potentially slow down the testing.
        void print(MutationStatusId statusId) {
            import dextool.plugin.mutate.backend.generate_mutant : makeMutationText;

            auto entry_ = spinSql!(() => ctx.state.get.db.mutantApi.getMutation(statusId));
            if (entry_.isNull)
                return;
            auto entry = entry_.get;

            try {
                const file = ctx.state.get.fio.toAbsoluteRoot(entry.file);
                auto txt = makeMutationText(ctx.state.get.fio.makeInput(file),
                        entry.mp.offset, entry.mp.mutations[0].kind, entry.lang);
                debug logger.trace(entry);
                logger.infof("from '%s' to '%s' in %s:%s:%s", txt.original,
                        txt.mutation, file, entry.sloc.line, entry.sloc.column);
            } catch (Exception e) {
                logger.info(e.msg).collectException;
            }
        }

        if (!ctx.state.get.isRunning)
            return;

        try {
            if (ctx.state.get.injectIds.empty) {
                logger.trace("no mutants left to test ", ctx.state.get.scheduler.free.length);
                if (ctx.state.get.activeSchemaCheck == State.ActiveSchemaCheck.noMutantTested
                        && ctx.state.get.scheduler.full) {
                    // no mutant has been tested in the schema thus the restore in save is never triggered.
                    send(ctx.self, RestoreMsg.init);
                    ctx.state.get.activeSchemaCheck = State.ActiveSchemaCheck.triggerRestoreOnce;
                }
                return;
            }

            if (ctx.state.get.scheduler.empty) {
                logger.trace("no free worker");
                delayedSend(ctx.self, 1.dur!"seconds".delay, ScheduleTestMsg.init);
                return;
            }

            if (ctx.state.get.stopCheck.isOverloaded) {
                logger.info(ctx.state.get.stopCheck.overloadToString).collectException;
                delayedSend(ctx.self, 30.dur!"seconds".delay, ScheduleTestMsg.init);
                return;
            }

            auto m = ctx.state.get.injectIds.front;
            ctx.state.get.injectIds.popFront;

            if (m.statusId in ctx.state.get.whiteList) {
                ctx.state.get.activeSchemaCheck = State.ActiveSchemaCheck.testing;
                auto testerId = ctx.state.get.scheduler.pop;
                auto tester = ctx.state.get.scheduler.get(testerId);
                print(m.statusId);
                ctx.self.request(tester, infTimeout).send(m).capture(ctx,
                        testerId).then((ref Capture!(Ctx, size_t) ctx, SchemaTestResult x) {
                    ctx[0].state.get.scheduler.put(ctx[1]);
                    send(ctx[0].self, x);
                    send(ctx[0].self, ScheduleTestMsg.init);
                });
            } else {
                debug logger.tracef("%s not in whitelist. Skipping", m);
                send(ctx.self, ScheduleTestMsg.init);
            }
        } catch (Exception e) {
            ctx.state.get.hasFatalError = true;
            ctx.state.get.isRunning = false;
            logger.error(e.msg).collectException;
        }
    }

    static void checkHaltCond(ref Ctx ctx, CheckStopCondMsg _) @safe nothrow {
        if (!ctx.state.get.isRunning)
            return;

        try {
            delayedSend(ctx.self, 5.dur!"seconds".delay, CheckStopCondMsg.init).collectException;

            const halt = ctx.state.get.stopCheck.isHalt;
            if (halt == TestStopCheck.HaltReason.overloaded)
                ctx.state.get.stopCheck.startBgShutdown;

            if (halt != TestStopCheck.HaltReason.none) {
                send(ctx.self, RestoreMsg.init);
                send(ctx.self, Stop.init);
                logger.info(ctx.state.get.stopCheck.overloadToString).collectException;
            }
        } catch (Exception e) {
            ctx.state.get.isRunning = false;
            logger.error(e.msg).collectException;
        }
    }

    static void stop(ref Ctx ctx, Stop _) @safe nothrow {
        ctx.state.get.isRunning = false;
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

    return impl(self, &init_, st, &isDone, st, &updateWlist, st,
            &doneStatus, st, &save, st, &mark, st, &injectAndCompile, st,
            &restore, st, &startTest, st, &test, st, &checkHaltCond, st,
            &generateSchema, st, &runSchema, st, &stop, st);
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
        Database db;
        SchemaBuildState schemaBuild;
        Set!MutationStatusId whiteList;
    }

    auto st = tuple!("self", "state")(self, refCounted(State(conf, sizeQUpdater)));
    alias Ctx = typeof(st);

    static void init_(ref Ctx ctx, Init _, AbsolutePath dbPath, ConfigSchema conf) nothrow {
        import dextool.plugin.mutate.backend.database : dbOpenTimeout;

        try {
            ctx.state.get.db = spinSql!(() => Database.make(dbPath), logger.trace)(dbOpenTimeout);

            ctx.state.get.schemaBuild.minMutantsPerSchema = ctx.state.get.conf.minMutantsPerSchema;
            ctx.state.get.schemaBuild.mutantsPerSchema.get = ctx.state.get.conf
                .mutantsPerSchema.get;
            ctx.state.get.schemaBuild.initFiles(
                    spinSql!(() => ctx.state.get.db.fileApi.getFileIds));
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            // TODO: should terminate?
        }
    }

    static void updateWhiteList(ref Ctx ctx, MutationStatusId[] whiteList) @trusted nothrow {
        try {
            ctx.state.get.whiteList = whiteList.toSet;
            send(ctx.state.get.sizeQUpdater, MutantsToTestMsg.init,
                    cast(long) ctx.state.get.whiteList.length);

            ctx.state.get.schemaBuild.builder.schemaQ = spinSql!(
                    () => SchemaQ(ctx.state.get.db.schemaApi.getMutantProbability));

            ctx.self.request(ctx.state.get.sizeQUpdater, infTimeout)
                .send(GetSchemaSizeMsg.init).capture(ctx).then((ref Ctx ctx, long sz) nothrow{
                ctx.state.get.schemaBuild.mutantsPerSchema.get = sz;
            });
        } catch (Exception e) {
        }
    }

    static GenSchemaResult genSchema(ref Ctx ctx, GenSchema _) nothrow {
        static void process(ref Ctx ctx, ref GenSchemaResult result,
                ref Set!MutationStatusId whiteList) @safe {
            auto value = ctx.state.get.schemaBuild.process;
            value.match!((Some!(SchemataBuilder.ET) a) {
                result.schema = a;
                result.injectIds = mutantsFromSchema(a, whiteList);
            }, (None a) {});
        }

        static void processFile(ref Ctx ctx, ref Set!MutationStatusId whiteList) @trusted nothrow {
            if (ctx.state.get.schemaBuild.files.isDone)
                return;

            size_t frags;
            while (frags == 0 && ctx.state.get.schemaBuild.files.filesLeft != 0) {
                logger.trace("Files left ",
                        ctx.state.get.schemaBuild.files.filesLeft).collectException;
                frags = spinSql!(() {
                    auto trans = ctx.state.get.db.transaction;
                    return ctx.state.get.schemaBuild.updateFiles(whiteList,
                        (FileId id) => spinSql!(() => ctx.state.get.db.schemaApi.getFragments(id)),
                        (FileId id) => spinSql!(() => ctx.state.get.db.getFile(id)),
                        (MutationStatusId id) => spinSql!(
                        () => ctx.state.get.db.mutantApi.getKind(id)));
                });
            }
        }

        GenSchemaResult result;

        logger.trace("Generate schema").collectException;
        while (ctx.state.get.schemaBuild.st != SchemaBuildState.State.done) {
            ctx.state.get.schemaBuild.tick;

            final switch (ctx.state.get.schemaBuild.st) {
            case SchemaBuildState.State.none:
                break;
            case SchemaBuildState.State.processFiles:
                try {
                    processFile(ctx, ctx.state.get.whiteList);
                    process(ctx, result, ctx.state.get.whiteList);
                } catch (Exception e) {
                    logger.trace(e.msg).collectException;
                    return GenSchemaResult(true);
                }
                break;
            case SchemaBuildState.State.prepareReduction:
                send(ctx.state.get.sizeQUpdater,
                        FullSchemaGenDoneMsg.init).collectException;
                goto case;
            case SchemaBuildState.State.prepareFinalize:
                try {
                    ctx.state.get.schemaBuild.files.reset;
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
                    processFile(ctx, ctx.state.get.whiteList);
                    process(ctx, result, ctx.state.get.whiteList);
                } catch (Exception e) {
                    logger.trace(e.msg).collectException;
                    return GenSchemaResult(true);
                }
                break;
            case SchemaBuildState.State.done:
                ctx.state.get.schemaBuild.files.clear;
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

    return impl(self, &init_, st, &genSchema, st, &updateWhiteList, st);
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

    static void updateMutantsNumber(ref Ctx ctx, MutantsToTestMsg _, long number) @safe nothrow {
        ctx.state.get.sizeQ.testMutantsSize = number;
    }

    static void genStatus(ref Ctx ctx, SchemaGenStatusMsg,
            SchemaStatus status, long mutantsInSchema) @safe nothrow {
        ctx.state.get.genCount++;
        try {
            ctx.state.get.sizeQ.update(status, mutantsInSchema);
            send(ctx.state.get.dbSave, ctx.state.get.sizeQ);
            logger.trace(ctx.state.get.sizeQ);
        } catch (Exception e) {
            logger.info(e.msg).collectException;
        }
    }

    static void fullGenDone(ref Ctx ctx, FullSchemaGenDoneMsg _) @safe nothrow {
        if (ctx.state.get.genCount == 0) {
            try {
                ctx.state.get.sizeQ.noCurrentSize;
                send(ctx.state.get.dbSave, ctx.state.get.sizeQ);
                logger.trace(ctx.state.get.sizeQ);
            } catch (Exception e) {
                logger.info(e.msg).collectException;
            }
        }
    }

    static long getSize(ref Ctx ctx, GetSchemaSizeMsg _) @safe nothrow {
        return ctx.state.get.sizeQ.currentSize;
    }

    self.name = "schemaSizeQUpdater";

    return impl(self, &updateMutantsNumber, st, &getSize, st, &genStatus,
            st, &fullGenDone, st);
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

/// Round robin scheduling of mutants for testing from the worker pool.
struct ScheduleTest {
    TestMutantActor.Address[] testers;
    Vector!size_t free;

    this(TestMutantActor.Address[] testers) {
        this.testers = testers;
        foreach (size_t i; 0 .. testers.length)
            free.put(i);
    }

    /// Returns: if the tester is full, no worker used.
    bool full() @safe pure nothrow const @nogc {
        return testers.length == free.length;
    }

    bool empty() @safe pure nothrow const @nogc {
        return free.empty;
    }

    size_t pop()
    in (free.length <= testers.length) {
        scope (exit)
            free.popFront();
        return free.front;
    }

    void put(size_t x)
    in (x < testers.length)
    out (; free.length <= testers.length)
    do {
        free.put(x);
    }

    TestMutantActor.Address get(size_t x)
    in (free.length <= testers.length)
    in (x < testers.length) {
        return testers[x];
    }

    void configure(TimeoutConfig conf) {
        foreach (a; testers)
            send(a, conf);
    }

}

struct SchemaTestResult {
    MutationTestResult result;
    Duration testTime;
    TestCase[] unstable;
}

alias TestMutantActor = typedActor!(
        SchemaTestResult function(InjectIdResult.InjectId id), void function(TimeoutConfig));

auto spawnTestMutant(TestMutantActor.Impl self, TestRunner runner, TestCaseAnalyzer analyzer) {
    static struct State {
        TestRunner runner;
        TestCaseAnalyzer analyzer;
    }

    auto st = tuple!("self", "state")(self, refCounted(State(runner, analyzer)));
    alias Ctx = typeof(st);

    static SchemaTestResult run(ref Ctx ctx, InjectIdResult.InjectId id) @safe nothrow {
        import std.datetime.stopwatch : StopWatch, AutoStart;
        import dextool.plugin.mutate.backend.analyze.pass_schemata : schemataMutantEnvKey;

        SchemaTestResult analyzeForTestCase(SchemaTestResult rval,
                ref DrainElement[][ShellCommand] output) @safe nothrow {
            foreach (testCmd; output.byKeyValue) {
                try {
                    auto analyze = ctx.state.get.analyzer.analyze(testCmd.key, testCmd.value);

                    analyze.match!((TestCaseAnalyzer.Success a) {
                        rval.result.testCases ~= a.failed ~ a.testCmd;
                    }, (TestCaseAnalyzer.Unstable a) {
                        rval.unstable ~= a.unstable;
                        // must re-test the mutant
                        rval.result.status = Mutation.Status.unknown;
                    }, (TestCaseAnalyzer.Failed a) {
                        logger.tracef("The parsers that analyze the output from %s failed",
                            testCmd.key);
                    });
                } catch (Exception e) {
                    logger.warning(e.msg).collectException;
                }
            }
            return rval;
        }

        auto sw = StopWatch(AutoStart.yes);

        SchemaTestResult rval;

        rval.result.id = id.statusId;

        auto env = ctx.state.get.runner.getDefaultEnv;
        env[schemataMutantEnvKey] = id.injectId.to!string;

        auto res = runTester(ctx.state.get.runner, env);
        rval.result.status = res.status;
        rval.result.exitStatus = res.exitStatus;
        rval.result.testCmds = res.output.byKey.array;

        if (!ctx.state.get.analyzer.empty)
            rval = analyzeForTestCase(rval, res.output);

        rval.testTime = sw.peek;
        return rval;
    }

    static void doConf(ref Ctx ctx, TimeoutConfig conf) @safe nothrow {
        ctx.state.get.runner.timeout = conf.value;
    }

    self.name = "testMutant";
    return impl(self, &run, st, &doConf, st);
}

// private:

import std.algorithm : sum;
import std.format : formattedWrite, format;

import dextool.plugin.mutate.backend.database.type : SchemataFragment;
import dextool.plugin.mutate.backend.type : Language, SourceLoc, Offset,
    SourceLocRange, CodeMutant, SchemataChecksum;
import dextool.plugin.mutate.backend.analyze.utility;

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

/** Build scheman from the fragments.
 *
 * TODO: optimize the implementation. A lot of redundant memory allocations
 * etc.
 *
 * Conservative to only allow up to <user defined> mutants per schemata but it
 * reduces the chance that one failing schemata is "fatal", loosing too many
 * muntats.
 */
struct SchemataBuilder {
    import std.algorithm : any, all;
    import my.container.vector;
    import dextool.plugin.mutate.backend.analyze.schema_ml : SchemaQ;
    import dextool.plugin.mutate.backend.database.type : SchemaFragmentV2;

    static struct SchemataFragment {
        Path file;
        Offset offset;
        const(ubyte)[] text;
    }

    static struct Fragment {
        SchemataFragment fragment;
        CodeMutant[] mutants;
    }

    static struct ET {
        SchemataFragment[] fragments;
        CodeMutant[] mutants;
        SchemataChecksum checksum;
    }

    // TODO: remove SchemataChecksum?

    /// Controls the probability that a mutant is part of the currently generating schema.
    SchemaQ schemaQ;

    /// use probability for if a mutant is injected or not
    bool useProbability;

    /// if the probability should also influence if the scheam is smaller.
    bool useProbablitySmallSize;

    // if fragments that are part of scheman that didn't reach the min
    // threshold should be discarded.
    bool discardMinScheman;

    /// The threshold start at this value.
    double thresholdStartValue = 0.0;

    /// Max mutants per schema.
    long mutantsPerSchema = 1000;

    /// Minimal mutants that a schema must contain for it to be valid.
    long minMutantsPerSchema = 3;

    Vector!Fragment current;
    Vector!Fragment rest;

    /// Size in bytes of the cache of fragments.
    size_t cacheSize;

    /** Merge analyze fragments into larger schemata fragments. If a schemata
     * fragment is large enough it is converted to a schemata. Otherwise kept
     * for pass2.
     *
     * Schematan from this pass only contain one kind and only affect one file.
     */
    void put(Fragment[] fragments) {
        foreach (a; fragments) {
            current.put(a);
            incrCache(a.fragment);
        }
    }

    private void incrCache(ref SchemataFragment a) @safe pure nothrow @nogc {
        cacheSize += a.text.length + (cast(const(ubyte)[]) a.file.toString).length + typeof(a)
            .sizeof;
    }

    bool empty() @safe pure nothrow const @nogc {
        return current.length == 0 && rest.length == 0;
    }

    auto stats() @safe pure nothrow const {
        static struct Stats {
            double cacheSizeMb;
            size_t current;
            size_t rest;
        }

        return Stats(cast(double) cacheSize / (1024 * 1024), current.length, rest.length);
    }

    /** Merge schemata fragments to schemas. A schemata from this pass may may
     * contain multiple mutation kinds and span over multiple files.
     */
    Optional!ET next() {
        import std.algorithm : max;

        Index!Path index;
        auto app = appender!(Fragment[])();
        Set!CodeMutant local;
        auto threshold() {
            return max(thresholdStartValue, cast(double) local.length / cast(double) mutantsPerSchema);
        }

        auto mutantsPerSchemaSmall = mutantsPerSchema;
        auto thresholdSmall() {
            return max(thresholdStartValue,
                    cast(double) local.length / cast(double) mutantsPerSchemaSmall);
        }

        bool loopCond() {
            if (current.empty || local.length >= mutantsPerSchema)
                return false;

            if (!useProbablitySmallSize)
                return true;
            if (local.length >= mutantsPerSchemaSmall)
                return false;

            mutantsPerSchemaSmall = max(mutantsPerSchemaSmall - minMutantsPerSchema,
                    minMutantsPerSchema);
            return true;
        }

        while (loopCond) {
            auto a = current.front;
            current.popFront;

            if (a.mutants.empty)
                continue;

            if (index.intersect(a.fragment.file, a.fragment.offset)) {
                rest.put(a);
                continue;
            }

            // if any of the mutants in the schema has already been included.
            if (any!(a => a in local)(a.mutants)) {
                rest.put(a);
                continue;
            }

            // if any of the mutants fail the probability to be included
            if (useProbability && any!(b => !schemaQ.use(a.fragment.file,
                    b.mut.kind, threshold()))(a.mutants)) {
                // TODO: remove this line of code in the future. used for now,
                // ugly, to see that it behavies as expected.
                //log.tracef("probability postpone fragment with mutants %s %s",
                //        a.mutants.length, a.mutants.map!(a => a.mut.kind));
                rest.put(a);
                continue;
            }

            // no use in using a mutant that has zero probability because then, it will always fail.
            if (any!(b => schemaQ.isZero(a.fragment.file, b.mut.kind))(a.mutants)) {
                continue;
            }

            if (useProbablitySmallSize && any!(b => !schemaQ.use(a.fragment.file,
                    b.mut.kind, thresholdSmall()))(a.mutants)) {
                rest.put(a);
                continue;
            }

            app.put(a);
            local.add(a.mutants);
            index.put(a.fragment.file, a.fragment.offset);
        }

        if (local.length == 0 || local.length < minMutantsPerSchema) {
            if (discardMinScheman) {
                logger.tracef("discarding %s fragments with %s mutants",
                        app.data.length, app.data.map!(a => a.mutants.length).sum);
            } else {
                rest.put(app.data);
            }
            return none!ET;
        }

        ET v;
        v.fragments = app.data.map!(a => a.fragment).array;
        v.mutants = local.toArray;
        v.checksum = toSchemataChecksum(v.mutants);

        return some(v);
    }

    bool isDone() @safe pure nothrow const @nogc {
        return current.empty;
    }

    void restart() @safe pure nothrow @nogc {
        current = rest;
        rest.clear;

        cacheSize = 0;
        foreach (a; current[])
            incrCache(a.fragment);
    }
}

/** A schema is uniquely identified by the mutants it contains.
 *
 * The order of the mutants are irrelevant because they are always sorted by
 * their value before the checksum is calculated.
 */
SchemataChecksum toSchemataChecksum(CodeMutant[] mutants) {
    import dextool.plugin.mutate.backend.utility : BuildChecksum, toChecksum, toBytes;

    BuildChecksum h;
    foreach (a; mutants.sort!((a, b) => a.id.value < b.id.value)
            .map!(a => a.id.value)) {
        h.put(a.c0.toBytes);
    }

    return SchemataChecksum(toChecksum(h));
}

/** The total state for building schemas in runtime.
 *
 * The intention isn't to perfectly travers and handle all mutants in the
 * worklist if the worklist is manipulated while the schema generation is
 * running. It is just "good enough" to generate schemas for those mutants when
 * it was started.
 */
struct SchemaBuildState {
    import std.sumtype;
    import my.optional;
    import dextool.plugin.mutate.backend.database.type : FileId, SchemaFragmentV2;

    enum State : ubyte {
        none,
        processFiles,
        prepareReduction,
        reduction,
        prepareFinalize,
        finalize1,
        finalize2,
        done,
    }

    static struct ProcessFiles {
        FileId[] files;
        size_t idx;

        FileId pop() @safe pure nothrow scope {
            if (idx == files.length)
                return FileId.init;
            return files[idx++];
        }

        bool isDone() @safe pure nothrow const @nogc scope {
            return idx == files.length;
        }

        size_t filesLeft() @safe pure nothrow const @nogc scope {
            return files.length - idx;
        }

        void reset() @safe pure nothrow @nogc scope {
            idx = 0;
        }

        void clear() @safe pure nothrow @nogc scope {
            files = null;
            reset;
        }
    }

    // State of the schema building
    State st;
    private int reducedTicks;

    // Files to use when generating schemas.
    ProcessFiles files;

    SchemataBuilder builder;

    // User configuration.
    typeof(ConfigSchema.minMutantsPerSchema) minMutantsPerSchema = 3;
    typeof(ConfigSchema.mutantsPerSchema) mutantsPerSchema = 1000;

    void initFiles(FileId[] files) @safe nothrow {
        import std.random : randomCover;

        try {
            // improve the schemas non-determinism between each `test` run.
            this.files.files = files.randomCover.array;
        } catch (Exception e) {
            this.files.files = files;
        }
    }

    /// Step through the schema building.
    void tick() @safe nothrow {
        logger.tracef("state_pre: %s %s", st, builder.stats).collectException;
        final switch (st) {
        case State.none:
            st = State.processFiles;
            try {
                setIntermediate;
            } catch (Exception e) {
                st = State.done;
            }
            break;
        case State.processFiles:
            if (files.isDone)
                st = State.prepareReduction;
            try {
                setIntermediate;
            } catch (Exception e) {
                st = State.done;
            }
            break;
        case State.prepareReduction:
            st = State.reduction;
            break;
        case State.reduction:
            immutable magic = 10; // reduce the size until it is 1/10 of the original
            immutable magic2 = 5; // if it goes <95% then it is too high probability to fail

            if (builder.empty)
                st = State.prepareFinalize;
            else if (++reducedTicks > (magic * magic2))
                st = State.prepareFinalize;

            try {
                setReducedIntermediate(1 + reducedTicks / magic, reducedTicks % magic2);
            } catch (Exception e) {
                st = State.done;
            }
            break;
        case State.prepareFinalize:
            st = State.finalize1;
            break;
        case State.finalize1:
            st = State.finalize2;
            try {
                finalize;
            } catch (Exception e) {
                st = State.done;
            }
            break;
        case State.finalize2:
            if (builder.isDone)
                st = State.done;
            break;
        case State.done:
            break;
        }
        logger.trace("state_post: ", st).collectException;
    }

    /// Add all fragments from one of the files to process to those to be
    /// incorporated into future schemas.
    /// Returns: number of fragments added.
    size_t updateFiles(ref Set!MutationStatusId whiteList, scope SchemaFragmentV2[]delegate(
            FileId) @safe fragmentsFn, scope Nullable!Path delegate(FileId) @safe fnameFn,
            scope Mutation.Kind delegate(MutationStatusId) @safe kindFn) @safe nothrow {
        import dextool.plugin.mutate.backend.type : CodeChecksum, Mutation;
        import dextool.plugin.mutate.backend.database : toChecksum;

        if (files.isDone)
            return 0;
        auto id = files.pop;
        try {
            const fname = fnameFn(id);
            if (fname.isNull)
                return 0;

            auto app = appender!(SchemataBuilder.Fragment[])();
            auto frags = fragmentsFn(id);
            foreach (a; frags) {
                auto cm = a.mutants
                    .filter!(a => a in whiteList)
                    .map!(a => CodeMutant(CodeChecksum(a.toChecksum),
                            Mutation(kindFn(a), Mutation.Status.unknown)))
                    .array;
                if (!cm.empty) {
                    app.put(SchemataBuilder.Fragment(SchemataBuilder.SchemataFragment(fname.get,
                            a.offset, a.text), cm));
                }
            }

            builder.put(app.data);
            return app.data.length;
        } catch (Exception e) {
            logger.trace(e.msg).collectException;
        }
        return 0;
    }

    Optional!(SchemataBuilder.ET) process() {
        auto rval = builder.next;
        builder.restart;
        return rval;
    }

    void setMinMutants(long desiredValue) {
        // seems like 200 Mbyte is large enough to generate scheman with >1000
        // mutants easily when running on LLVM.
        enum MaxCache = 200 * 1024 * 1024;
        if (builder.cacheSize > MaxCache) {
            // panic mode, just empty it as fast as possible.
            logger.infof(
                    "Schema cache is %s bytes (limit %s). Producing as many schemas as possible to flush the cache.",
                    builder.cacheSize, MaxCache);
            builder.minMutantsPerSchema = minMutantsPerSchema.get;
        } else {
            builder.minMutantsPerSchema = desiredValue;
        }
    }

    void setIntermediate() {
        logger.trace("schema generator phase: intermediate");
        builder.discardMinScheman = false;
        builder.useProbability = true;
        builder.useProbablitySmallSize = false;
        builder.mutantsPerSchema = mutantsPerSchema.get;
        builder.thresholdStartValue = 1.0;

        setMinMutants(mutantsPerSchema.get);
    }

    void setReducedIntermediate(long sizeDiv, long threshold) {
        import std.algorithm : max;

        logger.tracef("schema generator phase: reduced size:%s threshold:%s", sizeDiv, threshold);
        builder.discardMinScheman = false;
        builder.useProbability = true;
        builder.useProbablitySmallSize = false;
        builder.mutantsPerSchema = mutantsPerSchema.get;
        // TODO: interresting effect. this need to be studied. I think this
        // is the behavior that is "best".
        builder.thresholdStartValue = 1.0 - (cast(double) threshold / 100.0);

        setMinMutants(max(minMutantsPerSchema.get, mutantsPerSchema.get / sizeDiv));
    }

    /// Consume all fragments or discard.
    void finalize() {
        logger.trace("schema generator phase: finalize");
        builder.discardMinScheman = true;
        builder.useProbability = false;
        builder.useProbablitySmallSize = true;
        builder.mutantsPerSchema = mutantsPerSchema.get;
        builder.minMutantsPerSchema = minMutantsPerSchema.get;
        builder.thresholdStartValue = 0;
    }
}
