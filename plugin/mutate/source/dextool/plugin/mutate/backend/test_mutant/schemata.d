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
import std.typecons : Tuple, tuple;

import blob_model;
import colorlog;
import miniorm : spinSql, silentLog;
import my.actor;
import my.gc.refc;
import my.optional;
import my.container.vector;
import proc : DrainElement;
import sumtype;

import my.path;
import my.set;

import dextool.plugin.mutate.backend.database : MutationStatusId, Database,
    spinSql, SchemataId, Schemata;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
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

    struct UpdateWorkList {
    }

    struct Mark {
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

struct ConfTesters {
}

alias SchemaActor = typedActor!(void function(Init, AbsolutePath, ShellCommand, Duration),
        bool function(IsDone), void function(UpdateWorkList), FinalResult function(GetDoneStatus),
        void function(SchemaTestResult), void function(Mark, FinalResult.Status), void function(InjectAndCompile,
            ShellCommand, Duration), void function(RestoreMsg), void function(StartTestMsg),
        void function(ScheduleTestMsg), void function(CheckStopCondMsg), void function(ConfTesters));

auto spawnSchema(SchemaActor.Impl self, FilesysIO fio, ref TestRunner runner, AbsolutePath dbPath,
        TestCaseAnalyzer testCaseAnalyzer, ConfigSchema conf, SchemataId id,
        TestStopCheck stopCheck, Mutation.Kind[] kinds,
        ShellCommand buildCmd, Duration buildCmdTimeout, DbSaveActor.Address dbSave,
        StatActor.Address stat, TimeoutConfig timeoutConf) @trusted {

    static struct State {
        SchemataId id;
        Mutation.Kind[] kinds;
        TestStopCheck stopCheck;
        DbSaveActor.Address dbSave;
        StatActor.Address stat;
        TimeoutConfig timeoutConf;
        FilesysIO fio;
        TestRunner runner;
        TestCaseAnalyzer analyzer;
        ConfigSchema conf;

        Database db;

        AbsolutePath[] modifiedFiles;

        InjectIdResult injectIds;

        ScheduleTest scheduler;

        Set!MutationStatusId whiteList;

        Duration compileTime;

        int alive;

        bool hasFatalError;
        bool isInvalidSchema;

        bool isRunning;
    }

    auto st = tuple!("self", "state")(self, refCounted(State(id, kinds, stopCheck,
            dbSave, stat, timeoutConf, fio.dup, runner.dup, testCaseAnalyzer, conf)));
    alias Ctx = typeof(st);

    static void init_(ref Ctx ctx, Init _, AbsolutePath dbPath,
            ShellCommand buildCmd, Duration buildCmdTimeout) nothrow {
        import dextool.plugin.mutate.backend.database : dbOpenTimeout;

        try {
            ctx.state.get.db = spinSql!(() => Database.make(dbPath), logger.trace)(dbOpenTimeout);

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

            ctx.state.get.injectIds = mutantsFromSchema(ctx.state.get.db,
                    ctx.state.get.id, ctx.state.get.kinds);

            if (!ctx.state.get.injectIds.empty) {
                send(ctx.self, UpdateWorkList.init);
                send(ctx.self, InjectAndCompile.init, buildCmd, buildCmdTimeout);
                send(ctx.self, CheckStopCondMsg.init);

                ctx.state.get.isRunning = true;
            }
        } catch (Exception e) {
            ctx.state.get.hasFatalError = true;
            logger.error(e.msg).collectException;
        }
    }

    static void confTesters(ref Ctx ctx, ConfTesters _) {
        foreach (a; ctx.state.get.scheduler.testers) {
            send(a, ctx.state.get.timeoutConf);
        }
    }

    static bool isDone(ref Ctx ctx, IsDone _) {
        return !ctx.state.get.isRunning;
    }

    static void mark(ref Ctx ctx, Mark _, FinalResult.Status status) {
        import std.traits : EnumMembers;
        import dextool.plugin.mutate.backend.database : SchemaStatus;

        SchemaStatus schemaStatus;
        final switch (status) with (FinalResult.Status) {
        case fatalError:
            break;
        case invalidSchema:
            schemaStatus = SchemaStatus.broken;
            break;
        case ok:
            const total = spinSql!(() => ctx.state.get.db.schemaApi.countMutants(ctx.state.get.id,
                    ctx.state.get.kinds, [EnumMembers!(Mutation.Status)]));
            const killed = spinSql!(() => ctx.state.get.db.schemaApi.countMutants(ctx.state.get.id,
                    ctx.state.get.kinds, [
                        Mutation.Status.killed, Mutation.Status.timeout,
                        Mutation.Status.memOverload
                    ]));
            schemaStatus = (total == killed) ? SchemaStatus.allKilled : SchemaStatus.ok;
            break;
        }

        spinSql!(() => ctx.state.get.db.schemaApi.markUsed(ctx.state.get.id, schemaStatus));
    }

    static void updateWlist(ref Ctx ctx, UpdateWorkList _) @safe nothrow {
        if (!ctx.state.get.isRunning)
            return;

        delayedSend(ctx.self, 1.dur!"minutes".delay, UpdateWorkList.init).collectException;
        // TODO: should injectIds be updated too?

        try {
            ctx.state.get.whiteList = spinSql!(
                    () => ctx.state.get.db.schemaApi.getSchemataMutants(ctx.state.get.id,
                    ctx.state.get.kinds)).toSet;
            logger.trace("update schema worklist mutants: ", ctx.state.get.whiteList.length);
            debug logger.trace("update schema worklist: ", ctx.state.get.whiteList.toRange);
        } catch (Exception e) {
            logger.trace(e.msg).collectException;
        }
    }

    static FinalResult doneStatus(ref Ctx ctx, GetDoneStatus _) @safe nothrow {
        FinalResult.Status status = () {
            if (ctx.state.get.hasFatalError)
                return FinalResult.Status.fatalError;
            if (ctx.state.get.isInvalidSchema)
                return FinalResult.Status.invalidSchema;
            return FinalResult.Status.ok;
        }();

        if (!ctx.state.get.isRunning)
            send(ctx.self, Mark.init, status).collectException;

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

        if (ctx.state.get.injectIds.empty)
            send(ctx.self, RestoreMsg.init).collectException;
    }

    static void injectAndCompile(ref Ctx ctx, InjectAndCompile _,
            ShellCommand buildCmd, Duration buildCmdTimeout) @safe nothrow {
        try {
            auto sw = StopWatch(AutoStart.yes);
            scope (exit)
                ctx.state.get.compileTime = sw.peek;

            auto codeInject = CodeInject(ctx.state.get.fio, ctx.state.get.conf, ctx.state.get.id);
            ctx.state.get.modifiedFiles = codeInject.inject(ctx.state.get.db);
            codeInject.compile(buildCmd, buildCmdTimeout);

            if (ctx.state.get.conf.sanityCheckSchemata) {
                logger.info("Sanity check of the generated schemata");
                const sanity = sanityCheck(ctx.state.get.runner);
                if (sanity.isOk) {
                    if (ctx.state.get.timeoutConf.base < sanity.runtime) {
                        ctx.state.get.timeoutConf.set(sanity.runtime);
                        send(ctx.self, ConfTesters.init);
                    }

                    logger.info("Ok".color(Color.green), ". Using test suite timeout ",
                            ctx.state.get.timeoutConf.value).collectException;
                    send(ctx.self, StartTestMsg.init);
                } else {
                    logger.info("Skipping the schemata because the test suite failed".color(Color.yellow)
                            .toString);
                    ctx.state.get.isInvalidSchema = true;
                    send(ctx.self, RestoreMsg.init).collectException;
                }
            } else {
                send(ctx.self, StartTestMsg.init);
            }
        } catch (Exception e) {
            ctx.state.get.isInvalidSchema = true;
            send(ctx.self, RestoreMsg.init).collectException;
            logger.warning(e.msg).collectException;
        }
    }

    static void restore(ref Ctx ctx, RestoreMsg _) @safe nothrow {
        try {
            restoreFiles(ctx.state.get.modifiedFiles, ctx.state.get.fio);
            ctx.state.get.isRunning = false;
        } catch (Exception e) {
            ctx.state.get.hasFatalError = true;
            logger.error(e.msg).collectException;
        }
    }

    static void startTest(ref Ctx ctx, StartTestMsg _) @safe nothrow {
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

            auto id = spinSql!(() => ctx.state.get.db.mutantApi.getMutationId(statusId));
            if (id.isNull)
                return;
            auto entry_ = spinSql!(() => ctx.state.get.db.mutantApi.getMutation(id.get));
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

        try {
            if (!ctx.state.get.isRunning)
                return;

            if (ctx.state.get.injectIds.empty) {
                logger.trace("no mutants left to test");
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
                ctx.state.get.stopCheck.pause;
                return;
            }

            auto m = ctx.state.get.injectIds.front;
            ctx.state.get.injectIds.popFront;

            if (m.statusId in ctx.state.get.whiteList) {
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

            if (ctx.state.get.stopCheck.isHalt != TestStopCheck.HaltReason.none) {
                send(ctx.self, RestoreMsg.init);
                logger.info(ctx.state.get.stopCheck.overloadToString).collectException;
            }
        } catch (Exception e) {
        }
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
            &restore, st, &startTest, st, &test, st, &checkHaltCond, st, &confTesters, st);
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
}

/// Extract the mutants that are part of the schema.
InjectIdResult mutantsFromSchema(ref Database db, const SchemataId id, const Mutation.Kind[] kinds) {
    InjectIdBuilder builder;
    foreach (mutant; spinSql!(() => db.schemaApi.getSchemataMutants(id, kinds))) {
        auto cs = spinSql!(() => db.mutantApi.getChecksum(mutant));
        if (!cs.isNull)
            builder.put(mutant, cs.get);
    }
    debug logger.trace(builder);

    return builder.finalize;
}

@("shall detect a collision and make sure it is never part of the result")
unittest {
    InjectIdBuilder builder;
    builder.put(MutationStatusId(1), Checksum(1, 2));
    builder.put(MutationStatusId(2), Checksum(3, 4));
    builder.put(MutationStatusId(3), Checksum(1, 2));
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

    SchemataId schemataId;

    Set!AbsolutePath roots;

    bool logSchema;

    this(FilesysIO fio, ConfigSchema conf, SchemataId id) {
        this.fio = fio;
        this.schemataId = id;
        this.logSchema = conf.log;

        foreach (a; conf.userRuntimeCtrl) {
            auto p = fio.toAbsoluteRoot(a.file);
            roots.add(p);
        }
    }

    /// Throws an error on failure.
    /// Returns: modified files.
    AbsolutePath[] inject(ref Database db) {
        auto schemata = spinSql!(() => db.schemaApi.getSchemata(schemataId)).get;
        auto modifiedFiles = schemata.fragments.map!(a => fio.toAbsoluteRoot(a.file))
            .toSet.toRange.array;

        void initRoots(ref Database db) {
            if (roots.empty) {
                auto allRoots = () {
                    AbsolutePath[] tmp;
                    try {
                        tmp = spinSql!(() => db.getRootFiles).map!(a => db.getFile(a).get)
                            .map!(a => fio.toAbsoluteRoot(a))
                            .array;
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
            import dextool.plugin.mutate.backend.database.type : SchemataFragment;

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

                logger.info("Injecting schema in ", fname);

                // writing the schemata.
                auto s = makeSchemata(f, fragments(fio.toRelativeRoot(fname)), extra);
                fio.makeOutput(fname).write(s);

                if (logSchema) {
                    const ext = fname.toString.extension;
                    fio.makeOutput(AbsolutePath(format!"%s.%s.schema%s"(fname.toString.stripExtension,
                            schemataId.get, ext).Path)).write(s);
                }
            }
        }

        initRoots(db);
        injectCode;

        return modifiedFiles;
    }

    void compile(ShellCommand buildCmd, Duration buildCmdTimeout) {
        import dextool.plugin.mutate.backend.test_mutant.common : compile;

        logger.infof("Compile schema %s", schemataId.get).collectException;

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
