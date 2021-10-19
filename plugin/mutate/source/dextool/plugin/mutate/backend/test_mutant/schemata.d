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
import miniorm : spinSql, silentLog;
import my.actor;
import my.gc.refc;
import proc : DrainElement;
import sumtype;

import my.fsm : Fsm, next, act, get, TypeDataMap;
import my.path;
import my.set;
static import my.fsm;

import dextool.plugin.mutate.backend.database : MutationStatusId, Database,
    spinSql, SchemataId, Schemata;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.test_mutant.common;
import dextool.plugin.mutate.backend.test_mutant.common_actors : DbSaveActor, StatActor;
import dextool.plugin.mutate.backend.test_mutant.test_cmd_runner : TestRunner, TestResult;
import dextool.plugin.mutate.backend.test_mutant.timeout : TimeoutFsm;
import dextool.plugin.mutate.backend.type : Mutation, TestCase, Checksum;
import dextool.plugin.mutate.type : TestCaseAnalyzeBuiltin, ShellCommand,
    UserRuntime, SchemaRuntime;
import dextool.plugin.mutate.config : ConfigSchema;

@safe:

private {
    struct Init {
    }

    struct Tick {
    }

    struct UpdateWorkList {
    }

    struct SaveResult {
    }

    immutable pollWorklistPeriod = 1.dur!"minutes";
}

struct IsDone {
}

struct GetDoneStatus {
}

struct Mark {
}

struct FinalResult {
    enum Status {
        fatalError,
        invalidSchema,
        ok
    }

    Status status;
    int alive;
    TimeoutFsm timeoutFsm;
}

alias SchemaActor = typedActor!(void function(Init), bool function(IsDone), void function(Tick),
        void function(UpdateWorkList), FinalResult function(GetDoneStatus),
        void function(SaveResult), void function(Mark, FinalResult.Status));

auto spawnSchema(SchemaActor.Impl self, FilesysIO fio, TestRunner* runner, AbsolutePath dbPath,
        TestCaseAnalyzer* testCaseAnalyzer, ConfigSchema conf, SchemataId id,
        TestStopCheck stopCheck, Mutation.Kind[] kinds,
        ShellCommand buildCmd, Duration buildCmdTimeout,
        DbSaveActor.Address dbSave, StatActor.Address stat, TimeoutFsm timeoutFsm) @trusted {

    static struct State {
        SchemataId id;
        Mutation.Kind[] kinds;
        TestStopCheck stopCheck;
        DbSaveActor.Address dbSave;
        StatActor.Address stat;
        TimeoutFsm timeoutFsm;

        Database db;

        SchemataTestDriver driver;

        bool allKilled = true;
        int alive;
    }

    auto st = tuple!("self", "state")(self, refCounted(State(id, kinds,
            stopCheck, dbSave, stat, timeoutFsm)));
    alias Ctx = typeof(st);

    static void init_(ref Ctx ctx, Init _) {
        send(ctx.self, Tick.init);
    }

    static bool isDone(ref Ctx ctx, IsDone _) {
        return !ctx.state.get.driver.isRunning;
    }

    static void mark(ref Ctx ctx, Mark _, FinalResult.Status status) {
        import dextool.plugin.mutate.backend.database : SchemaStatus;

        SchemaStatus schemaStatus;
        final switch (status) with (FinalResult.Status) {
        case fatalError:
            break;
        case invalidSchema:
            schemaStatus = SchemaStatus.broken;
            break;
        case ok:
            schemaStatus = ctx.state.get.allKilled ? SchemaStatus.allKilled : SchemaStatus.ok;
            break;
        }

        spinSql!(() => ctx.state.get.db.schemaApi.markUsed(ctx.state.get.id, schemaStatus));
    }

    static void tick(ref Ctx ctx, Tick _) {
        for (int i = 0; i < 3 && ctx.state.get.driver.isRunning; ++i)
            ctx.state.get.driver.execute;
        if (ctx.state.get.driver.isRunning)
            send(ctx.self, Tick.init);
        if (ctx.state.get.driver.hasResult)
            send(ctx.self, SaveResult.init);
    }

    static void updateWlist(ref Ctx ctx, UpdateWorkList _) {
        if (!ctx.state.get.driver.isRunning)
            return;
        delayedSend(ctx.self, 1.dur!"minutes".delay, UpdateWorkList.init);

        try {
            auto wlist = spinSql!(() => ctx.state.get.db.schemaApi.getSchemataMutants(ctx.state.get.id,
                    ctx.state.get.kinds)).toSet;
            ctx.state.get.driver.putWorklist(wlist);
            debug logger.trace("update schema worklist: ", wlist.toRange);
        } catch (Exception e) {
            logger.trace(e.msg);
        }
    }

    static FinalResult doneStatus(ref Ctx ctx, GetDoneStatus _) {
        FinalResult.Status status = () {
            if (ctx.state.get.driver.hasFatalError)
                return FinalResult.Status.fatalError;
            if (ctx.state.get.driver.isInvalidSchema)
                return FinalResult.Status.invalidSchema;
            return FinalResult.Status.ok;
        }();

        if (!ctx.state.get.driver.isRunning)
            send(ctx.self, Mark.init, status);

        return FinalResult(status, ctx.state.get.alive, ctx.state.get.timeoutFsm);
    }

    static void save(ref Ctx ctx, SaveResult _) {
        import dextool.plugin.mutate.backend.test_mutant.common_actors : GetMutantsLeft,
            UnknownMutantTested;

        void update(MutationTestResult[] result) {
            // only remove if there actually are any results utherwise we do
            // not know if it is a good idea to remove it.
            // same with the overload. if mutation testing is stopped because
            // of a halt command then keep the schema.
            ctx.state.get.allKilled = ctx.state.get.allKilled
                && !(result.empty || ctx.state.get.stopCheck.isHalt != TestStopCheck
                        .HaltReason.none);

            foreach (a; result) {
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
                    ctx.state.get.allKilled = false;
                    ctx.state.get.alive++;
                    return;
                case killed:
                    goto case;
                case timeout:
                    goto case;
                case killedByCompiler:
                    break;
                }
            }
        }

        auto result = ctx.state.get.driver.popResult;
        if (result.empty)
            return;

        update(result);

        send(ctx.state.get.dbSave, result, ctx.state.get.timeoutFsm);
        send(ctx.state.get.stat, UnknownMutantTested.init, cast(long) result.length);

        // an error handler is required because the stat actor can be held up
        // for more than a minute.
        ctx.self.request(ctx.state.get.stat, delay(1.dur!"seconds"))
            .send(GetMutantsLeft.init).then((long x) {
                logger.infof("%s mutants left to test.", x);
            }, (ref Actor self, ErrorMsg) {});
    }

    import std.functional : toDelegate;
    import dextool.plugin.mutate.backend.database : dbOpenTimeout;

    self.name = "schemaDriver";
    self.exceptionHandler = toDelegate(&logExceptionHandler);
    try {
        st.state.get.db = spinSql!(() => Database.make(dbPath), logger.trace)(dbOpenTimeout);
        st.state.get.driver = SchemataTestDriver(fio, runner, &st.state.get.db,
                testCaseAnalyzer, conf, id, stopCheck, kinds, buildCmd, buildCmdTimeout);
        send(self, Init.init);
        send(self, UpdateWorkList.init);
    } catch (Exception e) {
        logger.error(e.msg).collectException;
        self.shutdown;
    }

    return impl(self, &init_, st, &isDone, st, &tick, st, &updateWlist, st,
            &doneStatus, st, &save, st, &mark, st);
}

struct SchemataTestDriver {
    private {
        /// True as long as the schemata driver is running.
        bool isRunning_ = true;
        bool hasFatalError_;
        bool isInvalidSchema_;

        FilesysIO fio;

        Database* db;

        /// Runs the test commands.
        TestRunner* runner;

        Mutation.Kind[] kinds;

        SchemataId schemataId;

        /// Result of testing the mutants.
        MutationTestResult[] result_;

        /// Time it took to compile the schemata.
        Duration compileTime;
        StopWatch swCompile;

        ShellCommand buildCmd;
        Duration buildCmdTimeout;

        /// The full schemata that is used..
        Schemata schemata;

        AbsolutePath[] modifiedFiles;

        Set!AbsolutePath roots;

        TestStopCheck stopCheck;

        ConfigSchema conf;
    }

    static struct None {
    }

    static struct Initialize {
        bool error;
    }

    static struct InitializeRoots {
        bool hasRoot;
    }

    static struct InjectSchema {
        bool error;
    }

    static struct Compile {
        bool error;
    }

    static struct Done {
    }

    static struct Restore {
        bool error;
    }

    static struct NextMutant {
        bool done;
        InjectIdResult.InjectId inject;
    }

    static struct NextMutantData {
        /// Mutants to test.
        InjectIdResult mutants;

        // updated each minute with the mutants that are in the worklist in
        // case there are multiple instances.
        Set!MutationStatusId whiteList;
    }

    static struct TestMutant {
        InjectIdResult.InjectId inject;

        MutationTestResult result;
        bool hasTestOutput;
        // if there are mutants status id's related to a file but the mutants
        // have been removed.
        bool mutantIdError;
    }

    static struct TestMutantData {
        /// If the user has configured that the test cases should be analyzed.
        bool hasTestCaseOutputAnalyzer;
    }

    static struct TestCaseAnalyzeData {
        TestCaseAnalyzer* testCaseAnalyzer;
        DrainElement[][ShellCommand] output;
    }

    static struct TestCaseAnalyze {
        MutationTestResult result;
        bool unstableTests;
    }

    static struct StoreResult {
        MutationTestResult result;
    }

    static struct OverloadCheck {
        bool halt;
        bool sleep;
    }

    alias Fsm = my.fsm.Fsm!(None, Initialize, InitializeRoots, Done, NextMutant, TestMutant,
            TestCaseAnalyze, StoreResult, InjectSchema, Compile, Restore, OverloadCheck);
    alias LocalStateDataT = Tuple!(TestMutantData, TestCaseAnalyzeData, NextMutantData);

    private {
        Fsm fsm;
        TypeDataMap!(LocalStateDataT, TestMutant, TestCaseAnalyze, NextMutant) local;
    }

    this(FilesysIO fio, TestRunner* runner, Database* db, TestCaseAnalyzer* testCaseAnalyzer,
            ConfigSchema conf, SchemataId id, TestStopCheck stopCheck,
            Mutation.Kind[] kinds, ShellCommand buildCmd, Duration buildCmdTimeout) {
        this.fio = fio;
        this.runner = runner;
        this.db = db;
        this.conf = conf;
        this.schemataId = id;
        this.stopCheck = stopCheck;
        this.kinds = kinds;
        this.buildCmd = buildCmd;
        this.buildCmdTimeout = buildCmdTimeout;

        this.local.get!TestCaseAnalyze.testCaseAnalyzer = testCaseAnalyzer;
        this.local.get!TestMutant.hasTestCaseOutputAnalyzer = !testCaseAnalyzer.empty;

        foreach (a; conf.userRuntimeCtrl) {
            auto p = fio.toAbsoluteRoot(a.file);
            roots.add(p);
        }

        if (logger.globalLogLevel.among(logger.LogLevel.trace, logger.LogLevel.all))
            fsm.logger = (string s) { logger.trace(s); };
    }

    static void execute_(ref SchemataTestDriver self) @trusted {
        self.fsm.next!((None a) => fsm(Initialize.init), (Initialize a) {
            if (a.error)
                return fsm(Done.init);
            if (self.conf.runtime == SchemaRuntime.inject)
                return fsm(InitializeRoots.init);
            return fsm(InjectSchema.init);
        }, (InitializeRoots a) {
            if (a.hasRoot)
                return fsm(InjectSchema.init);
            return fsm(Done.init);
        }, (InjectSchema a) {
            if (a.error)
                return fsm(Restore.init);
            return fsm(Compile.init);
        }, (Compile a) {
            if (a.error || self.conf.onlyCompile)
                return fsm(Restore.init);
            return fsm(OverloadCheck.init);
        }, (OverloadCheck a) {
            if (a.halt)
                return fsm(Restore.init);
            if (a.sleep)
                return fsm(OverloadCheck.init);
            return fsm(NextMutant.init);
        }, (NextMutant a) {
            if (a.done)
                return fsm(Restore.init);
            return fsm(TestMutant(a.inject));
        }, (TestMutant a) {
            if (a.mutantIdError)
                return fsm(OverloadCheck.init);
            if (a.result.status == Mutation.Status.killed
                && self.local.get!TestMutant.hasTestCaseOutputAnalyzer && a.hasTestOutput) {
                return fsm(TestCaseAnalyze(a.result));
            }
            return fsm(StoreResult(a.result));
        }, (TestCaseAnalyze a) {
            if (a.unstableTests)
                return fsm(OverloadCheck.init);
            return fsm(StoreResult(a.result));
        }, (StoreResult a) => fsm(OverloadCheck.init), (Restore a) => Done.init, (Done a) => a);

        self.fsm.act!(self);
    }

nothrow:

    void execute() {
        try {
            execute_(this);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    bool hasFatalError() {
        return hasFatalError_;
    }

    /// if the schema failed to compile or the test suite failed.
    bool isInvalidSchema() {
        return isInvalidSchema_;
    }

    bool isRunning() {
        return isRunning_;
    }

    bool hasResult() {
        return !result_.empty;
    }

    MutationTestResult[] popResult() {
        auto tmp = result_;
        result_ = null;
        return tmp;
    }

    void putWorklist(Set!MutationStatusId wlist) {
        local.get!NextMutant.whiteList = wlist;
    }

    void opCall(None data) {
    }

    void opCall(ref Initialize data) {
        import std.random : randomCover;

        swCompile = StopWatch(AutoStart.yes);

        InjectIdBuilder builder;
        foreach (mutant; spinSql!(() => db.schemaApi.getSchemataMutants(schemataId, kinds))
                .randomCover.array) {
            auto cs = spinSql!(() => db.mutantApi.getChecksum(mutant));
            if (!cs.isNull)
                builder.put(mutant, cs.get);
        }
        debug logger.trace(builder).collectException;

        local.get!NextMutant.mutants = builder.finalize;

        schemata = spinSql!(() => db.schemaApi.getSchemata(schemataId)).get;

        try {
            modifiedFiles = schemata.fragments.map!(a => fio.toAbsoluteRoot(a.file))
                .toSet.toRange.array;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            hasFatalError_ = true;
            data.error = true;
        }
    }

    void opCall(ref InitializeRoots data) {
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

        data.hasRoot = !roots.empty;

        if (roots.empty) {
            logger.warning("No root file found to inject the schemata runtime in").collectException;
        }
    }

    void opCall(Done data) {
        isRunning_ = false;
    }

    void opCall(ref InjectSchema data) {
        import std.path : extension, stripExtension;
        import dextool.plugin.mutate.backend.database.type : SchemataFragment;

        scope (exit)
            schemata = Schemata.init; // release the memory back to the GC

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

        try {
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

                if (conf.log) {
                    const ext = fname.toString.extension;
                    fio.makeOutput(AbsolutePath(format!"%s.%s.schema%s"(fname.toString.stripExtension,
                            schemataId.get, ext).Path)).write(s);

                    fio.makeOutput(AbsolutePath(format!"%s.%s.kinds.txt"(fname,
                            schemataId.get).Path)).write(format("%s", kinds));
                }
            }
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            data.error = true;
        }
    }

    void opCall(ref Compile data) {
        import colorlog;
        import dextool.plugin.mutate.backend.test_mutant.common : compile;

        logger.infof("Compile schema %s", schemataId.get).collectException;

        compile(buildCmd, buildCmdTimeout, PrintCompileOnFailure(true)).match!((Mutation.Status a) {
            data.error = true;
        }, (bool success) { data.error = !success; });

        if (data.error) {
            isInvalidSchema_ = true;

            logger.info("Skipping schema because it failed to compile".color(Color.yellow))
                .collectException;
            return;
        }

        logger.info("Ok".color(Color.green)).collectException;

        if (conf.sanityCheckSchemata) {
            try {
                logger.info("Sanity check of the generated schemata");
                auto res = runner.run;
                data.error = res.status != TestResult.Status.passed;
            } catch (Exception e) {
                logger.warning(e.msg).collectException;
            }

            if (data.error) {
                logger.info("Skipping the schemata because the test suite failed".color(Color.yellow))
                    .collectException;
                isInvalidSchema_ = true;
            } else {
                logger.info("Ok".color(Color.green)).collectException;
            }
        }

        compileTime = swCompile.peek;
    }

    void opCall(ref NextMutant data) @trusted {
        while (!local.get!NextMutant.mutants.empty) {
            auto m = local.get!NextMutant.mutants.front;
            local.get!NextMutant.mutants.popFront;

            if (m.statusId in local.get!NextMutant.whiteList) {
                data.inject = m;
                return;
            }
        }

        data.done = true;
    }

    void opCall(ref TestMutant data) {
        import std.datetime.stopwatch : StopWatch, AutoStart;
        import dextool.plugin.mutate.backend.analyze.pass_schemata : schemataMutantEnvKey,
            checksumToId;
        import dextool.plugin.mutate.backend.generate_mutant : makeMutationText;

        auto sw = StopWatch(AutoStart.yes);

        data.result.id = data.inject.statusId;

        auto id = spinSql!(() => db.mutantApi.getMutationId(data.inject.statusId));
        if (id.isNull) {
            data.mutantIdError = true;
            return;
        }
        auto entry_ = spinSql!(() => db.mutantApi.getMutation(id.get));
        if (entry_.isNull) {
            data.mutantIdError = true;
            return;
        }
        auto entry = entry_.get;

        try {
            const file = fio.toAbsoluteRoot(entry.file);
            auto txt = makeMutationText(fio.makeInput(file), entry.mp.offset,
                    entry.mp.mutations[0].kind, entry.lang);
            debug logger.trace(entry);
            logger.infof("from '%s' to '%s' in %s:%s:%s", txt.original,
                    txt.mutation, file, entry.sloc.line, entry.sloc.column);
        } catch (Exception e) {
            logger.info(e.msg).collectException;
        }

        auto env = runner.getDefaultEnv;
        env[schemataMutantEnvKey] = data.inject.injectId.to!string;

        auto res = runTester(*runner, env);
        data.result.profile = MutantTimeProfile(compileTime, sw.peek);
        // the first tested mutant also get the compile time of the schema.
        compileTime = Duration.zero;

        data.result.mutId = id.get;
        data.result.status = res.status;
        data.result.exitStatus = res.exitStatus;
        data.hasTestOutput = !res.output.empty;
        local.get!TestCaseAnalyze.output = res.output;

        logger.infof("%s:%s (%s)", data.result.status,
                data.result.exitStatus.get, data.result.profile).collectException;
        logger.tracef("%s %s injectId:%s", id, data.result.id,
                data.inject.injectId).collectException;
    }

    void opCall(ref TestCaseAnalyze data) {
        scope (exit)
            local.get!TestCaseAnalyze.output = null;

        foreach (testCmd; local.get!TestCaseAnalyze.output.byKeyValue) {
            try {
                auto analyze = local.get!TestCaseAnalyze.testCaseAnalyzer.analyze(testCmd.key,
                        testCmd.value);

                analyze.match!((TestCaseAnalyzer.Success a) {
                    data.result.testCases ~= a.failed ~ a.testCmd;
                }, (TestCaseAnalyzer.Unstable a) {
                    logger.warningf("Unstable test cases found: [%-(%s, %)]", a.unstable);
                    logger.info(
                        "As configured the result is ignored which will force the mutant to be re-tested");
                    data.unstableTests = true;
                }, (TestCaseAnalyzer.Failed a) {
                    logger.warning("The parser that analyze the output from test case(s) failed");
                });
            } catch (Exception e) {
                logger.warning(e.msg).collectException;
            }
        }

        logger.infof(!data.result.testCases.empty, `killed by [%-(%s, %)]`,
                data.result.testCases.sort.map!"a.name").collectException;
    }

    void opCall(StoreResult data) {
        result_ ~= data.result;
    }

    void opCall(ref OverloadCheck data) {
        data.halt = stopCheck.isHalt != TestStopCheck.HaltReason.none;
        data.sleep = stopCheck.isOverloaded;

        if (data.sleep) {
            logger.info(stopCheck.overloadToString).collectException;
            stopCheck.pause;
        }
    }

    void opCall(ref Restore data) {
        try {
            restoreFiles(modifiedFiles, fio);
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            data.error = true;
            hasFatalError_ = true;
        }
    }
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

    InjectIdResult finalize() @safe pure nothrow {
        import std.array : array;

        return InjectIdResult(result.byValue.array);
    }
}

struct InjectIdResult {
    alias InjectId = Tuple!(MutationStatusId, "statusId", uint, "injectId");
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
