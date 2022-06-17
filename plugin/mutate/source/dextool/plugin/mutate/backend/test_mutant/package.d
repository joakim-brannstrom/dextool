/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.test_mutant;

import core.time : Duration, dur;
import logger = std.experimental.logger;
import std.algorithm : map, filter, joiner, among, max;
import std.array : empty, array, appender;
import std.datetime : SysTime, Clock;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.exception : collectException;
import std.format : format;
import std.random : randomCover;
import std.traits : EnumMembers;
import std.typecons : Nullable, Tuple, Yes, tuple;

import blob_model : Blob;
import miniorm : spinSql, silentLog;
import my.actor;
import my.container.vector;
import my.fsm : Fsm, next, act, get, TypeDataMap;
import my.gc.refc;
import my.hash : Checksum64;
import my.named_type;
import my.optional;
import my.set;
import proc : DrainElement;
import sumtype;
static import my.fsm;

import dextool.plugin.mutate.backend.database : Database, MutationEntry,
    NextMutationEntry, TestFile, ChecksumTestCmdOriginal;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.test_mutant.common;
import dextool.plugin.mutate.backend.test_mutant.test_cmd_runner : TestRunner,
    findExecutables, TestRunResult = TestResult;
import dextool.plugin.mutate.backend.test_mutant.common_actors : DbSaveActor, StatActor;
import dextool.plugin.mutate.backend.test_mutant.timeout : TimeoutFsm;
import dextool.plugin.mutate.backend.type : Mutation, TestCase, ExitStatus;
import dextool.plugin.mutate.config;
import dextool.plugin.mutate.type : ShellCommand;
import dextool.type : AbsolutePath, ExitStatusType, Path;

@safe:

auto makeTestMutant() {
    return BuildTestMutant();
}

private:

struct BuildTestMutant {
@safe:

    import dextool.plugin.mutate.type : MutationKind;

    private struct InternalData {
        Mutation.Kind[] kinds;
        FilesysIO filesys_io;
        ConfigMutationTest config;
        ConfigSchema schemaConf;
        ConfigCoverage covConf;
    }

    private InternalData data;

    auto config(ConfigMutationTest c) @trusted nothrow {
        data.config = c;
        return this;
    }

    auto config(ConfigSchema c) @trusted nothrow {
        data.schemaConf = c;
        return this;
    }

    auto config(ConfigCoverage c) @trusted nothrow {
        data.covConf = c;
        return this;
    }

    auto mutations(MutationKind[] v) nothrow {
        import dextool.plugin.mutate.backend.mutation_type : toInternal;

        logger.infof("mutation operators: %(%s, %)", v).collectException;
        data.kinds = toInternal(v);
        return this;
    }

    ExitStatusType run(const AbsolutePath dbPath, FilesysIO fio) @trusted {
        try {
            auto db = spinSql!(() => Database.make(dbPath))(dbOpenTimeout);
            return internalRun(dbPath, &db, fio);
        } catch (Exception e) {
            logger.error(e.msg).collectException;
        }

        return ExitStatusType.Errors;
    }

    private ExitStatusType internalRun(AbsolutePath dbPath, Database* db, FilesysIO fio) {
        auto system = makeSystem;

        auto cleanup = new AutoCleanup;
        scope (exit)
            cleanup.cleanup;

        auto test_driver = TestDriver(dbPath, db, () @trusted { return &system; }(),
                fio, data.kinds, cleanup, data.config, data.covConf, data.schemaConf);

        while (test_driver.isRunning) {
            test_driver.execute;
        }

        return test_driver.status;
    }
}

struct MeasureTestDurationResult {
    bool ok;
    Duration[] runtime;
}

/** Measure the time it takes to run the test command.
 *
 * The runtime is the lowest of three executions. Anything else is assumed to
 * be variations in the system.
 *
 * If the tests fail (exit code isn't 0) any time then they are too unreliable
 * to use for mutation testing.
 *
 * Params:
 *  runner = ?
 *  samples = number of times to run the test suite
 */
MeasureTestDurationResult measureTestCommand(ref TestRunner runner, int samples) @safe nothrow {
    import std.algorithm : min;
    import proc;

    if (runner.empty) {
        collectException(logger.error("No test command(s) specified (--test-cmd)"));
        return MeasureTestDurationResult(false);
    }

    static struct Rval {
        TestRunResult result;
        Duration runtime;
    }

    auto runTest() @safe {
        auto sw = StopWatch(AutoStart.yes);
        auto res = runner.run(4.dur!"hours");
        return Rval(res, sw.peek);
    }

    static void print(TestRunResult res) @trusted {
        import std.stdio : stdout, write;

        foreach (kv; res.output.byKeyValue) {
            logger.info("test_cmd: ", kv.key);
            foreach (l; kv.value)
                write(l.byUTF8);
        }

        stdout.flush;
    }

    static void printFailing(ref TestRunResult res) {
        print(res);
        logger.info("failing commands: ", res.output.byKey);
        logger.info("exit status: ", res.exitStatus.get);
    }

    Duration[] runtimes;
    bool failed;
    for (int i; i < samples && !failed; ++i) {
        try {
            auto res = runTest;
            final switch (res.result.status) with (TestRunResult) {
            case Status.passed:
                runtimes ~= res.runtime;
                break;
            case Status.failed:
                goto case;
            case Status.timeout:
                goto case;
            case Status.memOverload:
                goto case;
            case Status.error:
                failed = true;
                printFailing(res.result);
                break;
            }
            logger.infof("%s: Measured test command runtime %s", i, res.runtime);
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            failed = true;
        }
    }

    return MeasureTestDurationResult(!failed, runtimes);
}

struct TestDriver {
    import std.datetime : SysTime;
    import dextool.plugin.mutate.backend.database : SchemataId, MutationStatusId;
    import dextool.plugin.mutate.backend.test_mutant.source_mutant : MutationTestDriver;
    import dextool.plugin.mutate.backend.test_mutant.timeout : TimeoutFsm, TimeoutConfig;
    import dextool.plugin.mutate.type : MutationOrder;

    Database* db;
    AbsolutePath dbPath;

    FilesysIO filesysIO;
    Mutation.Kind[] kinds;
    AutoCleanup autoCleanup;

    ConfigMutationTest conf;
    ConfigSchema schemaConf;
    ConfigCoverage covConf;

    System* system;

    /// Async communication with the database
    DbSaveActor.Address dbSave;

    /// Async stat update from the database every 30s.
    StatActor.Address stat;

    /// Runs the test commands.
    TestRunner runner;

    ///
    TestCaseAnalyzer testCaseAnalyzer;

    /// Stop conditions (most of them)
    TestStopCheck stopCheck;

    /// assuming that there are no more than 100 instances running in
    /// parallel.
    uint maxParallelInstances;

    // need to use 10000 because in an untested code base it is not
    // uncommon for mutants being in the thousands.
    enum long unknownWeight = 10000;
    // using a factor 1000 to make a pull request mutant very high prio
    enum long pullRequestWeight = unknownWeight * 1000;

    TimeoutFsm timeoutFsm;

    /// the next mutant to test, if there are any.
    MutationEntry nextMutant;

    TimeoutConfig timeout;

    /// Test commands to execute.
    ShellCommand[] testCmds;

    // The order to test mutants. It is either affected by the user directly or if pull request mode is activated.
    MutationOrder mutationOrder;

    static struct UpdateTimeoutData {
        long lastTimeoutIter;
    }

    static struct None {
    }

    static struct Initialize {
        bool halt;
    }

    static struct PullRequest {
    }

    static struct PullRequestData {
        import dextool.plugin.mutate.type : TestConstraint;

        TestConstraint constraint;
    }

    static struct SanityCheck {
        bool sanityCheckFailed;
    }

    static struct AnalyzeTestCmdForTestCase {
        bool failed;
        TestCase[][ShellCommand] foundTestCases;
    }

    static struct UpdateAndResetAliveMutants {
        TestCase[][ShellCommand] foundTestCases;
    }

    static struct RetestOldMutant {
    }

    static struct ResetOldMutantData {
        /// Number of mutants that where reset.
        long maxReset;
        NamedType!(double, Tag!"OldMutantPercentage", double.init, TagStringable) resetPercentage;
    }

    static struct Cleanup {
    }

    static struct CheckMutantsLeft {
        bool allMutantsTested;
    }

    static struct SaveMutationScore {
    }

    static struct UpdateTestCaseTag {
    }

    static struct ParseStdin {
    }

    static struct PreCompileSut {
        bool compilationError;
    }

    static struct FindTestCmds {
    }

    static struct UpdateTestCmds {
    }

    static struct ChooseMode {
    }

    static struct MeasureTestSuite {
        bool unreliableTestSuite;
    }

    static struct MutationTest {
        NamedType!(bool, Tag!"MutationError", bool.init, TagStringable) mutationError;
        MutationTestResult[] result;
    }

    static struct MutationTestData {
        TestBinaryDb testBinaryDb;
    }

    static struct CheckTimeout {
        bool timeoutUnchanged;
    }

    static struct NextSchemataData {
        SchemataId[] schematas;
        long totalSchematas;
        long invalidSchematas;
    }

    static struct NextSchemata {
        NamedType!(bool, Tag!"HasSchema", bool.init, TagStringable, ImplicitConvertable) hasSchema;
        SchemataId schemataId;

        /// stop mutation testing because the last schema has been used and the
        /// user has configured that the testing should stop now.
        NamedType!(bool, Tag!"StopTesting", bool.init, TagStringable, ImplicitConvertable) stop;
    }

    static struct SchemataTest {
        SchemataId id;
        bool fatalError;
    }

    static struct Done {
    }

    static struct Error {
    }

    static struct UpdateTimeout {
    }

    static struct CheckPullRequestMutant {
        NamedType!(bool, Tag!"NoUnknown", bool.init, TagStringable, ImplicitConvertable) noUnknownMutantsLeft;
    }

    static struct CheckPullRequestMutantData {
        long startWorklistCnt;
        long stopAfter;
    }

    static struct NextMutant {
        NamedType!(bool, Tag!"NoUnknown", bool.init, TagStringable, ImplicitConvertable) noUnknownMutantsLeft;
    }

    static struct NextMutantData {
        import dextool.plugin.mutate.backend.database.type : MutationId;

        // because of the asynchronous nature it may be so that the result of
        // the last executed hasn't finished being written to the DB when we
        // request a new mutant. This is used to block repeating the same
        // mutant.
        MutationId lastTested;
    }

    static struct HandleTestResult {
        MutationTestResult[] result;
    }

    static struct CheckStopCond {
        bool halt;
    }

    static struct LoadSchematas {
    }

    static struct OverloadCheck {
        bool sleep;
    }

    static struct ContinuesCheckTestSuite {
        bool ok;
    }

    static struct ContinuesCheckTestSuiteData {
        long lastWorklistCnt;
        SysTime lastCheck;
    }

    static struct Stop {
    }

    static struct Coverage {
        bool propagate;
        bool fatalError;
    }

    static struct PropagateCoverage {
    }

    static struct ChecksumTestCmds {
    }

    static struct SaveTestBinary {
    }

    alias Fsm = my.fsm.Fsm!(None, Initialize, SanityCheck,
            AnalyzeTestCmdForTestCase, UpdateAndResetAliveMutants, RetestOldMutant,
            Cleanup, CheckMutantsLeft, PreCompileSut, MeasureTestSuite, NextMutant,
            MutationTest, HandleTestResult, CheckTimeout, Done, Error,
            UpdateTimeout, CheckStopCond, PullRequest,
            CheckPullRequestMutant, ParseStdin, FindTestCmds, UpdateTestCmds, ChooseMode,
            NextSchemata, SchemataTest, LoadSchematas, Stop, SaveMutationScore,
            UpdateTestCaseTag, OverloadCheck, Coverage, PropagateCoverage,
            ContinuesCheckTestSuite, ChecksumTestCmds, SaveTestBinary);
    alias LocalStateDataT = Tuple!(UpdateTimeoutData, CheckPullRequestMutantData, PullRequestData, ResetOldMutantData,
            NextSchemataData, ContinuesCheckTestSuiteData, MutationTestData, NextMutantData);

    private {
        Fsm fsm;
        TypeDataMap!(LocalStateDataT, UpdateTimeout, CheckPullRequestMutant, PullRequest,
                RetestOldMutant, NextSchemata, ContinuesCheckTestSuite, MutationTest, NextMutant) local;
        bool isRunning_ = true;
        bool isDone = false;
    }

    this(AbsolutePath dbPath, Database* db, System* sys, FilesysIO filesysIO, Mutation.Kind[] kinds,
            AutoCleanup autoCleanup, ConfigMutationTest conf,
            ConfigCoverage coverage, ConfigSchema schema) {
        this.db = db;
        this.dbPath = dbPath;

        this.system = sys;

        this.filesysIO = filesysIO;
        this.kinds = kinds;
        this.autoCleanup = autoCleanup;
        this.conf = conf;
        this.covConf = coverage;
        this.schemaConf = schema;

        this.timeoutFsm = TimeoutFsm(kinds);

        if (!conf.mutationTesterRuntime.isNull)
            timeout.userConfigured(conf.mutationTesterRuntime.get);

        local.get!PullRequest.constraint = conf.constraint;
        local.get!RetestOldMutant.maxReset = conf.oldMutantsNr;
        local.get!RetestOldMutant.resetPercentage = conf.oldMutantPercentage;
        this.testCmds = conf.mutationTester;
        this.mutationOrder = conf.mutationOrder;

        this.runner.useEarlyStop(conf.useEarlyTestCmdStop);
        this.runner = TestRunner.make(conf.testPoolSize);
        this.runner.useEarlyStop(conf.useEarlyTestCmdStop);
        this.runner.maxOutputCapture(
                TestRunner.MaxCaptureBytes(conf.maxTestCaseOutput.get * 1024 * 1024));
        this.runner.minAvailableMem(
                TestRunner.MinAvailableMemBytes(toMinMemory(conf.maxMemUsage.get)));
        this.runner.put(conf.mutationTester);

        // TODO: allow a user, as is for test_cmd, to specify an array of
        // external analyzers.
        this.testCaseAnalyzer = TestCaseAnalyzer(conf.mutationTestCaseBuiltin,
                conf.mutationTestCaseAnalyze, autoCleanup);

        this.stopCheck = TestStopCheck(conf);

        this.maxParallelInstances = () {
            if (mutationOrder.among(MutationOrder.random, MutationOrder.bySize))
                return 100;
            return 1;
        }();

        if (logger.globalLogLevel.among(logger.LogLevel.trace, logger.LogLevel.all))
            fsm.logger = (string s) { logger.trace(s); };
    }

    static void execute_(ref TestDriver self) @trusted {
        // see test_mutant/basis.md and figures/test_mutant_fsm.pu for a
        // graphical view of the state machine.

        self.fsm.next!((None a) => fsm(Initialize.init), (Initialize a) {
            if (a.halt)
                return fsm(CheckStopCond.init);
            return fsm(SanityCheck.init);
        }, (SanityCheck a) {
            if (a.sanityCheckFailed)
                return fsm(Error.init);
            if (self.conf.unifiedDiffFromStdin)
                return fsm(ParseStdin.init);
            return fsm(PreCompileSut.init);
        }, (ParseStdin a) => fsm(PreCompileSut.init), (AnalyzeTestCmdForTestCase a) {
            if (a.failed)
                return fsm(Error.init);
            return fsm(UpdateAndResetAliveMutants(a.foundTestCases));
        }, (UpdateAndResetAliveMutants a) {
            if (self.conf.onOldMutants == ConfigMutationTest.OldMutant.test)
                return fsm(RetestOldMutant.init);
            return fsm(CheckMutantsLeft.init);
        }, (RetestOldMutant a) => fsm(CheckMutantsLeft.init), (Cleanup a) {
            if (self.local.get!PullRequest.constraint.empty)
                return fsm(NextSchemata.init);
            return fsm(CheckPullRequestMutant.init);
        }, (CheckMutantsLeft a) {
            if (a.allMutantsTested)
                return fsm(Done.init);
            if (self.conf.testCmdChecksum.get)
                return fsm(ChecksumTestCmds.init);
            return fsm(MeasureTestSuite.init);
        }, (ChecksumTestCmds a) => MeasureTestSuite.init, (SaveMutationScore a) => UpdateTestCaseTag.init,
                (UpdateTestCaseTag a) => SaveTestBinary.init,
                (SaveTestBinary a) => Stop.init, (PreCompileSut a) {
            if (a.compilationError)
                return fsm(Error.init);
            if (self.conf.testCommandDir.empty)
                return fsm(UpdateTestCmds.init);
            return fsm(FindTestCmds.init);
        }, (FindTestCmds a) => fsm(UpdateTestCmds.init),
                (UpdateTestCmds a) => fsm(ChooseMode.init), (ChooseMode a) {
            if (!self.local.get!PullRequest.constraint.empty)
                return fsm(PullRequest.init);
            if (!self.conf.mutationTestCaseAnalyze.empty
                || !self.conf.mutationTestCaseBuiltin.empty)
                return fsm(AnalyzeTestCmdForTestCase.init);
            if (self.conf.onOldMutants == ConfigMutationTest.OldMutant.test)
                return fsm(RetestOldMutant.init);
            return fsm(CheckMutantsLeft.init);
        }, (PullRequest a) => fsm(CheckMutantsLeft.init), (MeasureTestSuite a) {
            if (a.unreliableTestSuite)
                return fsm(Error.init);
            if (self.covConf.use && self.local.get!PullRequest.constraint.empty)
                return fsm(Coverage.init);
            return fsm(LoadSchematas.init);
        }, (Coverage a) {
            if (a.fatalError)
                return fsm(Error.init);
            if (a.propagate)
                return fsm(PropagateCoverage.init);
            return fsm(LoadSchematas.init);
        }, (PropagateCoverage a) => LoadSchematas.init,
                (LoadSchematas a) => fsm(UpdateTimeout.init), (CheckPullRequestMutant a) {
            if (a.noUnknownMutantsLeft)
                return fsm(Done.init);
            return fsm(NextMutant.init);
        }, (NextSchemata a) {
            if (a.hasSchema)
                return fsm(SchemataTest(a.schemataId));
            if (a.stop)
                return fsm(Done.init);
            return fsm(NextMutant.init);
        }, (SchemataTest a) {
            if (a.fatalError)
                return fsm(Error.init);
            return fsm(CheckStopCond.init);
        }, (NextMutant a) {
            if (a.noUnknownMutantsLeft)
                return fsm(CheckTimeout.init);
            return fsm(MutationTest.init);
        }, (UpdateTimeout a) => fsm(OverloadCheck.init), (OverloadCheck a) {
            if (a.sleep)
                return fsm(CheckStopCond.init);
            return fsm(ContinuesCheckTestSuite.init);
        }, (ContinuesCheckTestSuite a) {
            if (a.ok)
                return fsm(Cleanup.init);
            return fsm(Error.init);
        }, (MutationTest a) {
            if (a.mutationError)
                return fsm(Error.init);
            return fsm(HandleTestResult(a.result));
        }, (HandleTestResult a) => fsm(CheckStopCond.init), (CheckStopCond a) {
            if (a.halt)
                return fsm(Done.init);
            return fsm(UpdateTimeout.init);
        }, (CheckTimeout a) {
            if (a.timeoutUnchanged)
                return fsm(Done.init);
            return fsm(UpdateTimeout.init);
        }, (Done a) => fsm(SaveMutationScore.init), (Error a) => fsm(Stop.init), (Stop a) => fsm(a));

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

    bool isRunning() {
        return isRunning_;
    }

    ExitStatusType status() {
        if (isDone)
            return ExitStatusType.Ok;
        return ExitStatusType.Errors;
    }

    void opCall(None data) {
    }

    void opCall(ref Initialize data) {
        logger.info("Initializing worklist").collectException;

        auto status = [Mutation.Status.unknown];
        if (!conf.useSkipMutant)
            status ~= Mutation.Status.skipped;

        spinSql!(() {
            db.worklistApi.update(kinds, status, unknownWeight, mutationOrder);
        });

        // detect if the system is overloaded before trying to do something
        // slow such as compiling the SUT.
        if (conf.loadBehavior == ConfigMutationTest.LoadBehavior.halt && stopCheck.isHalt) {
            data.halt = true;
        }

        logger.infof("Memory limit set minium %s Mbyte",
                cast(ulong)(toMinMemory(conf.maxMemUsage.get) / (1024.0 * 1024.0)))
            .collectException;

        try {
            dbSave = system.spawn(&spawnDbSaveActor, dbPath);
            stat = system.spawn(&spawnStatActor, dbPath);
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            data.halt = true;
        }
    }

    void opCall(Stop data) {
        isRunning_ = false;
    }

    void opCall(Done data) {
        import dextool.plugin.mutate.backend.test_mutant.common_actors : IsDone;

        try {
            auto self = scopedActor;
            // it should NOT take more than five minutes to save the last
            // results to the database.
            self.request(dbSave, delay(5.dur!"minutes")).send(IsDone.init).then((bool a) {
            });
        } catch (ScopedActorException e) {
            logger.trace(e.error).collectException;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }

        logger.info("Done!").collectException;
        isDone = true;
    }

    void opCall(Error data) {
        autoCleanup.cleanup;
    }

    void opCall(ref SanityCheck data) {
        import core.sys.posix.sys.stat : S_IWUSR;
        import std.path : buildPath;
        import my.file : getAttrs;
        import colorlog : color;
        import dextool.plugin.mutate.backend.utility : checksum, Checksum;

        logger.info("Sanity check of files to mutate").collectException;

        auto failed = appender!(string[])();
        auto checksumFailed = appender!(string[])();
        auto writePermissionFailed = appender!(string[])();
        foreach (file; spinSql!(() { return db.getFiles; })) {
            auto db_checksum = spinSql!(() { return db.getFileChecksum(file); });

            try {
                auto abs_f = AbsolutePath(buildPath(filesysIO.getOutputDir, file));
                auto f_checksum = checksum(filesysIO.makeInput(abs_f).content[]);
                if (db_checksum != f_checksum) {
                    checksumFailed.put(abs_f);
                }

                uint attrs;
                if (getAttrs(abs_f, attrs)) {
                    if ((attrs & S_IWUSR) == 0) {
                        writePermissionFailed.put(abs_f);
                    }
                } else {
                    writePermissionFailed.put(abs_f);
                }
            } catch (Exception e) {
                failed.put(file);
                logger.warningf("%s: %s", file, e.msg).collectException;
            }
        }

        data.sanityCheckFailed = !failed.data.empty
            || !checksumFailed.data.empty || !writePermissionFailed.data.empty;

        if (data.sanityCheckFailed) {
            logger.info(!failed.data.empty,
                    "Unknown error when checking the files").collectException;
            foreach (f; failed.data)
                logger.info(f).collectException;

            logger.info(!checksumFailed.data.empty,
                    "Detected that file(s) has changed since last analyze where done")
                .collectException;
            logger.info(!checksumFailed.data.empty,
                    "Either restore the file(s) or rerun the analyze").collectException;
            foreach (f; checksumFailed.data)
                logger.info(f).collectException;

            logger.info(!writePermissionFailed.data.empty,
                    "Files to mutate are not writable").collectException;
            foreach (f; writePermissionFailed.data)
                logger.info(f).collectException;

            logger.info("Failed".color.fgRed).collectException;
        } else {
            logger.info("Ok".color.fgGreen).collectException;
        }
    }

    void opCall(ref OverloadCheck data) {
        if (conf.loadBehavior == ConfigMutationTest.LoadBehavior.slowdown && stopCheck.isOverloaded) {
            data.sleep = true;
            logger.info(stopCheck.overloadToString).collectException;
            stopCheck.pause;
        }
    }

    void opCall(ref ContinuesCheckTestSuite data) {
        import colorlog : color;

        data.ok = true;

        if (!conf.contCheckTestSuite)
            return;

        enum forceCheckEach = 1.dur!"hours";

        const wlist = spinSql!(() => db.worklistApi.getCount);
        if (local.get!ContinuesCheckTestSuite.lastWorklistCnt == 0) {
            // first time, just initialize.
            local.get!ContinuesCheckTestSuite.lastWorklistCnt = wlist;
            local.get!ContinuesCheckTestSuite.lastCheck = Clock.currTime + forceCheckEach;
            return;
        }

        const period = conf.contCheckTestSuitePeriod.get;
        const diffCnt = local.get!ContinuesCheckTestSuite.lastWorklistCnt - wlist;
        // period == 0 is mostly for test purpose because it makes it possible
        // to force a check for every mutant.
        if (!(period == 0 || wlist % period == 0 || diffCnt >= period
                || Clock.currTime > local.get!ContinuesCheckTestSuite.lastCheck))
            return;

        logger.info("Checking the test environment").collectException;

        local.get!ContinuesCheckTestSuite.lastWorklistCnt = wlist;
        local.get!ContinuesCheckTestSuite.lastCheck = Clock.currTime + forceCheckEach;

        compile(conf.mutationCompile, conf.buildCmdTimeout, PrintCompileOnFailure(true)).match!(
                (Mutation.Status a) { data.ok = false; }, (bool success) {
            data.ok = success;
        });

        if (data.ok) {
            try {
                data.ok = measureTestCommand(runner, 1).ok;
            } catch (Exception e) {
                logger.error(e.msg).collectException;
                data.ok = false;
            }
        }

        if (data.ok) {
            logger.info("Ok".color.fgGreen).collectException;
        } else {
            logger.info("Failed".color.fgRed).collectException;
            logger.warning("Continues sanity check of the test suite has failed.").collectException;
            logger.infof("Rolling back the status of the last %s mutants to status unknown.",
                    period).collectException;
            foreach (a; spinSql!(() => db.mutantApi.getLatestMutants(kinds, max(diffCnt, period)))) {
                spinSql!(() => db.mutantApi.update(a.id, Mutation.Status.unknown,
                        ExitStatus(0), MutantTimeProfile.init));
            }
        }
    }

    void opCall(ParseStdin data) {
        import dextool.plugin.mutate.backend.diff_parser : diffFromStdin;
        import dextool.plugin.mutate.type : Line;

        try {
            auto constraint = local.get!PullRequest.constraint;
            foreach (pkv; diffFromStdin.toRange(filesysIO.getOutputDir)) {
                constraint.value[pkv.key] ~= pkv.value.toRange.map!(a => Line(a)).array;
            }
            local.get!PullRequest.constraint = constraint;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    void opCall(ref AnalyzeTestCmdForTestCase data) {
        import std.conv : to;
        import colorlog : color;

        TestCase[][ShellCommand] found;

        try {
            runner.captureAll(true);
            scope (exit)
                runner.captureAll(false);

            // using an unreasonable timeout to make it possible to analyze for
            // test cases and measure the test suite.
            auto res = runTester(runner, 999.dur!"hours");
            data.failed = res.status != Mutation.Status.alive;

            foreach (testCmd; res.output.byKeyValue) {
                auto analyze = testCaseAnalyzer.analyze(testCmd.key, testCmd.value, Yes.allFound);

                analyze.match!((TestCaseAnalyzer.Success a) {
                    found[testCmd.key] = a.found;
                }, (TestCaseAnalyzer.Unstable a) {
                    logger.warningf("Unstable test cases found: [%-(%s, %)]", a.unstable);
                    found[testCmd.key] = a.found;
                }, (TestCaseAnalyzer.Failed a) {
                    logger.warning("The parser that analyze the output for test case(s) failed");
                });
            }

            if (data.failed) {
                logger.infof("Some or all tests have status %s (exit code %s)",
                        res.status.to!string.color.fgRed, res.exitStatus.get);
                try {
                    // TODO: this is a lazy way to execute the test suite again
                    // to show the failing tests. prettify....
                    measureTestCommand(runner, 1);
                } catch (Exception e) {
                }
                logger.warning("Failing test suite");
            }

            warnIfConflictingTestCaseIdentifiers(found.byValue.joiner.array);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }

        if (!data.failed) {
            data.foundTestCases = found;
        }
    }

    void opCall(UpdateAndResetAliveMutants data) {
        // the test cases before anything has potentially changed.
        auto old_tcs = spinSql!(() {
            Set!string old_tcs;
            foreach (tc; db.testCaseApi.getDetectedTestCases)
                old_tcs.add(tc.name);
            return old_tcs;
        });

        void transaction() @safe {
            final switch (conf.onRemovedTestCases) with (ConfigMutationTest.RemovedTestCases) {
            case doNothing:
                db.testCaseApi.addDetectedTestCases(data.foundTestCases.byValue.joiner.array);
                break;
            case remove:
                bool update;
                // change all mutants which, if a test case is removed, no
                // longer has a test case that kills it to unknown status
                foreach (id; db.testCaseApi.setDetectedTestCases(
                        data.foundTestCases.byValue.joiner.array)) {
                    if (!db.testCaseApi.hasTestCases(id)) {
                        update = true;
                        db.mutantApi.update(id, Mutation.Status.unknown, ExitStatus(0));
                    }
                }
                if (update) {
                    db.worklistApi.update(kinds, [
                            Mutation.Status.unknown, Mutation.Status.skipped
                            ]);
                }
                break;
            }
        }

        auto found_tcs = spinSql!(() @trusted {
            auto tr = db.transaction;
            transaction();

            Set!string found_tcs;
            foreach (tc; db.testCaseApi.getDetectedTestCases)
                found_tcs.add(tc.name);

            tr.commit;
            return found_tcs;
        });

        printDroppedTestCases(old_tcs, found_tcs);

        if (hasNewTestCases(old_tcs, found_tcs)
                && conf.onNewTestCases == ConfigMutationTest.NewTestCases.resetAlive) {
            logger.info("Adding alive mutants to worklist").collectException;
            spinSql!(() {
                db.worklistApi.update(kinds, [
                        Mutation.Status.alive, Mutation.Status.skipped,
                        // if these mutants are covered by the tests then they will be
                        // removed from the worklist in PropagateCoverage.
                        Mutation.Status.noCoverage
                    ]);
            });
        }
    }

    void opCall(RetestOldMutant data) {
        import std.range : enumerate;
        import dextool.plugin.mutate.backend.database.type;
        import dextool.plugin.mutate.backend.test_mutant.timeout : resetTimeoutContext;

        const statusTypes = [EnumMembers!(Mutation.Status)].filter!(
                a => a != Mutation.Status.noCoverage).array;

        void printStatus(T0)(T0 oldestMutant, SysTime newestTest, SysTime newestFile) {
            logger.info("Tests last changed ", newestTest).collectException;
            logger.info("Source code last changed ", newestFile).collectException;

            if (!oldestMutant.empty) {
                logger.info("The oldest mutant is ", oldestMutant[0].updated).collectException;
            }
        }

        if (conf.onOldMutants == ConfigMutationTest.OldMutant.nothing)
            return;

        // do not add mutants to worklist if there already are mutants there
        // because other states and functions need it to sooner or late reach
        // zero.
        const wlist = spinSql!(() => db.worklistApi.getCount);
        if (wlist != 0)
            return;

        const oldestMutant = spinSql!(() => db.mutantApi.getOldestMutants(kinds, 1, statusTypes));
        const newestTest = spinSql!(() => db.testFileApi.getNewestTestFile).orElse(
                TestFile.init).timeStamp;
        const newestFile = spinSql!(() => db.getNewestFile).orElse(SysTime.init);
        if (!oldestMutant.empty && oldestMutant[0].updated > newestTest
                && oldestMutant[0].updated > newestFile) {
            // only re-test old mutants if needed.
            logger.info("Mutation status is up to date").collectException;
            printStatus(oldestMutant, newestTest, newestFile);
            return;
        } else {
            logger.info("Mutation status is out of sync").collectException;
            printStatus(oldestMutant, newestTest, newestFile);
        }

        const long testCnt = () {
            if (local.get!RetestOldMutant.resetPercentage.get == 0.0) {
                return local.get!RetestOldMutant.maxReset;
            }

            const total = spinSql!(() => db.mutantApi.totalSrcMutants(kinds).count);
            const rval = cast(long)(1 + total
                    * local.get!RetestOldMutant.resetPercentage.get / 100.0);
            return rval;
        }();

        spinSql!(() {
            auto oldest = db.mutantApi.getOldestMutants(kinds, testCnt, statusTypes);
            logger.infof("Adding %s old mutants to the worklist", oldest.length);
            foreach (const old; oldest) {
                db.worklistApi.add(old.id);
            }
            if (oldest.length > 3) {
                logger.infof("Range of when the added mutants where last tested is %s -> %s",
                    oldest[0].updated, oldest[$ - 1].updated);
            }

            // because the mutants are zero it is assumed that they it is
            // starting from scratch thus the timeout algorithm need to
            // re-start from its initial state.
            logger.info("Resetting timeout context");
            resetTimeoutContext(*db);
        });
    }

    void opCall(Cleanup data) {
        autoCleanup.cleanup;
    }

    void opCall(ref CheckMutantsLeft data) {
        spinSql!(() { timeoutFsm.execute(*db); });

        data.allMutantsTested = timeoutFsm.output.done;

        if (timeoutFsm.output.done) {
            logger.info("All mutants are tested").collectException;
        }
    }

    void opCall(ChecksumTestCmds data) @trusted {
        import std.file : exists;
        import my.hash : Checksum64, makeCrc64Iso, checksum;
        import dextool.plugin.mutate.backend.database.type : ChecksumTestCmdOriginal;

        auto previous = spinSql!(() => db.testCmdApi.original);

        try {
            Set!Checksum64 current;

            void helper() {
                // clearing just to be on the safe side if helper is called
                // multiple times and a checksum is different between the
                // calls..... shouldn't happen but
                current = typeof(current).init;
                auto tr = db.transaction;

                foreach (testCmd; hashFiles(testCmds.filter!(a => !a.empty)
                        .map!(a => a.value[0]))) {
                    current.add(testCmd.cs);

                    if (testCmd.cs !in previous)
                        db.testCmdApi.set(testCmd.file, ChecksumTestCmdOriginal(testCmd.cs));
                }

                foreach (a; previous.setDifference(current).toRange) {
                    const name = db.testCmdApi.getTestCmd(ChecksumTestCmdOriginal(a));
                    if (!name.empty)
                        db.testCmdApi.clearTestCmdToMutant(name);
                    db.testCmdApi.remove(ChecksumTestCmdOriginal(a));
                }

                tr.commit;
            }

            // the operation must succeed as a whole or fail.
            spinSql!(() => helper);

            local.get!MutationTest.testBinaryDb.original = current;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }

        local.get!MutationTest.testBinaryDb.mutated = spinSql!(
                () @trusted => db.testCmdApi.mutated);
    }

    void opCall(SaveMutationScore data) {
        import dextool.plugin.mutate.backend.database.type : MutationScore;
        import dextool.plugin.mutate.backend.report.analyzers : reportScore, reportScores;

        if (spinSql!(() => db.mutantApi.unknownSrcMutants(kinds)).count != 0)
            return;
        // users are unhappy when the score go first up and then down because
        // mutants are first classified as "timeout" (killed) and then changed
        // to alive when the timeout is increased. This lead to a trend graph
        // that always looks like /\ which inhibit the "motivational drive" to
        // work with mutation testing.  Thus if there are any timeout mutants
        // to test, do not sample the score. It avoids the "hill" behavior in
        // the trend.
        if (spinSql!(() => db.timeoutApi.countMutantTimeoutWorklist) != 0)
            return;

        auto files = spinSql!(() => db.getFilesStrings());

        const fileScores = reportScores(*db, kinds, files);
        const score = reportScore(*db, kinds);
        const time = Clock.currTime;
        // 10000 mutation scores is only ~80kbyte. Should be enough entries
        // without taking up unreasonable amount of space.

        spinSql!(() @trusted {
            auto t = db.transaction;
            db.putMutationScore(MutationScore(time, typeof(MutationScore.score)(score.score)));
            db.trimMutationScore(10000);
            t.commit;
        });

        foreach(fileScore; fileScores){
            spinSql!(() @trusted {
                auto t = db.transaction;
                db.putMutationFileScore(MutationScore(time, typeof(MutationScore.score)(fileScore.score), fileScore.filePath));
                db.trimMutationScore(10000);
                t.commit;
            });
        }
    }

    void opCall(UpdateTestCaseTag data) {
        if (spinSql!(() => db.worklistApi.getCount([
                    Mutation.Status.alive, Mutation.Status.unknown
                ])) == 0) {
            spinSql!(() => db.testCaseApi.removeNewTestCaseTag);
            logger.info("All alive in worklist tested. Removing 'new test' tag.").collectException;
        }
    }

    void opCall(SaveTestBinary data) {
        if (!local.get!MutationTest.testBinaryDb.empty)
            saveTestBinaryDb(local.get!MutationTest.testBinaryDb);
    }

    void opCall(ref PreCompileSut data) {
        import proc;

        logger.info("Checking the build command").collectException;
        compile(conf.mutationCompile, conf.buildCmdTimeout, PrintCompileOnFailure(true)).match!(
                (Mutation.Status a) { data.compilationError = true; }, (bool success) {
            data.compilationError = !success;
        });
    }

    void opCall(FindTestCmds data) {
        auto cmds = appender!(ShellCommand[])();
        foreach (root; conf.testCommandDir) {
            try {
                cmds.put(findExecutables(root.AbsolutePath, () {
                        import std.file : SpanMode;

                        final switch (conf.testCmdDirSearch) with (
                            ConfigMutationTest.TestCmdDirSearch) {
                        case shallow:
                            return SpanMode.shallow;
                        case recursive:
                            return SpanMode.breadth;
                        }
                    }()).map!(a => ShellCommand([a] ~ conf.testCommandDirFlag)));
            } catch (Exception e) {
                logger.warning(e.msg).collectException;
            }
        }

        if (!cmds.data.empty) {
            testCmds ~= cmds.data;
            runner.put(this.testCmds);
            logger.infof("Found test commands in %s:", conf.testCommandDir).collectException;
            foreach (c; cmds.data) {
                logger.info(c).collectException;
            }
        }
    }

    void opCall(UpdateTestCmds data) {
        spinSql!(() @trusted {
            auto tr = db.transaction;
            db.testCmdApi.set(runner.testCmds.map!(a => a.cmd.toString).array);
            tr.commit;
        });
    }

    void opCall(ChooseMode data) {
    }

    void opCall(PullRequest data) {
        import std.algorithm : sort;
        import my.set;
        import dextool.plugin.mutate.backend.database : MutationStatusId;
        import dextool.plugin.mutate.backend.type : SourceLoc;

        // deterministic testing of mutants and prioritized by their size.
        mutationOrder = MutationOrder.bySize;
        maxParallelInstances = 1;

        // make sure they are unique.
        Set!MutationStatusId mutantIds;

        foreach (kv; local.get!PullRequest.constraint.value.byKeyValue) {
            const file_id = spinSql!(() => db.getFileId(kv.key));
            if (file_id.isNull) {
                logger.infof("The file %s do not exist in the database. Skipping...",
                        kv.key).collectException;
                continue;
            }

            foreach (l; kv.value) {
                auto mutants = spinSql!(() => db.mutantApi.getMutationsOnLine(kinds,
                        file_id.get, SourceLoc(l.value, 0)));

                const preCnt = mutantIds.length;
                foreach (v; mutants)
                    mutantIds.add(v);

                logger.infof(mutantIds.length - preCnt > 0, "Found %s mutant(s) to test (%s:%s)",
                        mutantIds.length - preCnt, kv.key, l.value).collectException;
            }
        }

        logger.infof(!mutantIds.empty, "Found %s mutants in the diff",
                mutantIds.length).collectException;
        spinSql!(() {
            foreach (id; mutantIds.toArray.sort)
                db.worklistApi.add(id, pullRequestWeight, MutationOrder.bySize);
        });

        local.get!CheckPullRequestMutant.startWorklistCnt = spinSql!(() => db.worklistApi.getCount);
        local.get!CheckPullRequestMutant.stopAfter = mutantIds.length;

        if (mutantIds.empty) {
            logger.warning("None of the locations specified with -L exists").collectException;
            logger.info("Available files are:").collectException;
            foreach (f; spinSql!(() => db.getFiles))
                logger.info(f).collectException;
        }
    }

    void opCall(ref MeasureTestSuite data) {
        import std.algorithm : sum;
        import dextool.plugin.mutate.backend.database.type : TestCmdRuntime;

        if (timeout.isUserConfig) {
            runner.timeout = timeout.base;
            return;
        }

        logger.infof("Measuring the runtime of the test command(s):\n%(%s\n%)",
                testCmds).collectException;

        auto measures = spinSql!(() => db.testCmdApi.getTestCmdRuntimes);

        const tester = () {
            try {
                return measureTestCommand(runner, max(1, cast(int)(3 - measures.length)));
            } catch (Exception e) {
                logger.error(e.msg).collectException;
                return MeasureTestDurationResult(false);
            }
        }();

        if (tester.ok) {
            measures ~= tester.runtime.map!(a => TestCmdRuntime(Clock.currTime, a)).array;
            if (measures.length > 3) {
                measures = measures[1 .. $]; // drop the oldest
            }

            auto mean = sum(measures.map!(a => a.runtime), Duration.zero) / measures.length;
            logger.info("Test command runtime: ", mean).collectException;
            timeout.set(mean);
            runner.timeout = timeout.value;

            spinSql!(() @trusted {
                auto t = db.transaction;
                db.testCmdApi.setTestCmdRuntimes(measures);
                t.commit;
            });
        } else {
            data.unreliableTestSuite = true;
            logger.error("The test command is unreliable. It must return exit status '0' when no mutants are injected")
                .collectException;
        }
    }

    void opCall(ref MutationTest data) @trusted {
        auto runnerPtr = () @trusted { return &runner; }();
        auto testBinaryDbPtr = () @trusted {
            return &local.get!MutationTest.testBinaryDb;
        }();

        try {
            auto g = MutationTestDriver.Global(filesysIO, db, nextMutant,
                    runnerPtr, testBinaryDbPtr, conf.useSkipMutant);
            auto driver = MutationTestDriver(g,
                    MutationTestDriver.TestMutantData(!(conf.mutationTestCaseAnalyze.empty
                        && conf.mutationTestCaseBuiltin.empty),
                        conf.mutationCompile, conf.buildCmdTimeout),
                    MutationTestDriver.TestCaseAnalyzeData(&testCaseAnalyzer));

            while (driver.isRunning) {
                driver.execute();
            }

            if (driver.stopBecauseError) {
                data.mutationError.get = true;
            } else {
                data.result = driver.result;
            }
        } catch (Exception e) {
            data.mutationError.get = true;
            logger.error(e.msg).collectException;
        }
    }

    void opCall(ref CheckTimeout data) {
        data.timeoutUnchanged = timeout.isUserConfig || timeoutFsm.output.done;
    }

    void opCall(UpdateTimeout) {
        spinSql!(() { timeoutFsm.execute(*db); });

        const lastIter = local.get!UpdateTimeout.lastTimeoutIter;

        if (lastIter != timeoutFsm.output.iter) {
            const old = timeout.value;
            timeout.updateIteration(timeoutFsm.output.iter);
            logger.infof("Changed the timeout from %s to %s (iteration %s)",
                    old, timeout.value, timeoutFsm.output.iter).collectException;
            local.get!UpdateTimeout.lastTimeoutIter = timeoutFsm.output.iter;
        }

        runner.timeout = timeout.value;
    }

    void opCall(ref CheckPullRequestMutant data) {
        const left = spinSql!(() => db.worklistApi.getCount);
        data.noUnknownMutantsLeft.get = (
                local.get!CheckPullRequestMutant.startWorklistCnt - left) >= local
            .get!CheckPullRequestMutant.stopAfter;

        logger.infof(stopCheck.aliveMutants > 0, "Found %s/%s alive mutants",
                stopCheck.aliveMutants, conf.maxAlive.get).collectException;
    }

    void opCall(ref NextMutant data) {
        nextMutant = MutationEntry.init;

        // it is OK to re-test the same mutant thus using a somewhat short timeout. It isn't fatal.
        const giveUpAfter = Clock.currTime + 30.dur!"seconds";
        NextMutationEntry next;
        while (Clock.currTime < giveUpAfter) {
            next = spinSql!(() => db.nextMutation(kinds, maxParallelInstances));

            if (next.st == NextMutationEntry.Status.done)
                break;
            else if (!next.entry.isNull && next.entry.get.id != local.get!NextMutant.lastTested)
                break;
            else if (next.entry.isNull)
                break;
        }

        data.noUnknownMutantsLeft.get = next.st == NextMutationEntry.Status.done;

        if (!next.entry.isNull) {
            nextMutant = next.entry.get;
            local.get!NextMutant.lastTested = next.entry.get.id;
        }
    }

    void opCall(HandleTestResult data) {
        saveTestResult(data.result);
        if (!local.get!MutationTest.testBinaryDb.empty)
            saveTestBinaryDb(local.get!MutationTest.testBinaryDb);
    }

    void opCall(ref CheckStopCond data) {
        const halt = stopCheck.isHalt;
        data.halt = halt != TestStopCheck.HaltReason.none;

        final switch (halt) with (TestStopCheck.HaltReason) {
        case none:
            break;
        case maxRuntime:
            logger.info(stopCheck.maxRuntimeToString).collectException;
            break;
        case aliveTested:
            logger.info("Alive mutants threshold reached").collectException;
            break;
        case overloaded:
            logger.info(stopCheck.overloadToString).collectException;
            break;
        }
        logger.warning(data.halt, "Halting").collectException;
    }

    void opCall(ref NextSchemata data) {
        auto schematas = local.get!NextSchemata.schematas;

        const threshold = schemataMutantsThreshold(schemaConf.minMutantsPerSchema.get,
                local.get!NextSchemata.invalidSchematas, local.get!NextSchemata.totalSchematas);

        while (!schematas.empty && !data.hasSchema) {
            // TODO: replace with my.collection.vector
            const id = schematas[0];
            schematas = schematas[1 .. $];
            const mutants = spinSql!(() => db.schemaApi.countMutantsInWorklist(id, kinds));

            logger.infof("Schema %s has %s mutants (threshold %s)", id.get,
                    mutants, threshold).collectException;

            if (mutants >= threshold) {
                data.hasSchema.get = true;
                data.schemataId = id;
                logger.infof("Use schema %s (%s/%s)", id.get, local.get!NextSchemata.totalSchematas - schematas.length,
                        local.get!NextSchemata.totalSchematas).collectException;
            }
        }

        local.get!NextSchemata.schematas = schematas;

        data.stop.get = !data.hasSchema && schemaConf.stopAfterLastSchema;
    }

    void opCall(ref SchemataTest data) {
        import core.thread : Thread;
        import core.time : dur;
        import dextool.plugin.mutate.backend.database : SchemaStatus;
        import dextool.plugin.mutate.backend.test_mutant.schemata;

        try {
            auto driver = system.spawn(&spawnSchema, filesysIO, runner, dbPath, testCaseAnalyzer, schemaConf,
                    data.id, stopCheck, kinds, conf.mutationCompile,
                    conf.buildCmdTimeout, dbSave, stat, timeout);
            scope (exit)
                sendExit(driver, ExitReason.userShutdown);
            auto self = scopedActor;

            {
                bool waiting = true;
                while (waiting) {
                    try {
                        self.request(driver, infTimeout).send(IsDone.init).then((bool x) {
                            waiting = !x;
                        });
                    } catch (ScopedActorException e) {
                        if (e.error != ScopedActorError.timeout) {
                            logger.trace(e.error);
                            return;
                        }
                    }
                    () @trusted { Thread.sleep(100.dur!"msecs"); }();
                }
            }

            FinalResult fr;
            {
                try {
                    self.request(driver, delay(1.dur!"minutes"))
                        .send(GetDoneStatus.init).then((FinalResult x) { fr = x; });
                    logger.trace("final schema status ", fr.status);
                } catch (ScopedActorException e) {
                    logger.trace(e.error);
                    return;
                }
            }

            final switch (fr.status) with (FinalResult.Status) {
            case fatalError:
                data.fatalError = true;
                break;
            case invalidSchema:
                local.get!NextSchemata.invalidSchematas++;
                break;
            case ok:
                break;
            }

            stopCheck.incrAliveMutants(fr.alive);
        } catch (Exception e) {
            logger.info(e.msg).collectException;
            logger.warning("Failed executing schemata ", data.id).collectException;
            spinSql!(() => db.schemaApi.markUsed(data.id, SchemaStatus.broken));
        }
    }

    void opCall(LoadSchematas data) {
        import dextool.plugin.mutate.backend.database.type : SchemaStatus;

        if (!schemaConf.use) {
            return;
        }

        auto app = appender!(SchemataId[])();
        foreach (id; spinSql!(() => db.schemaApi.getSchematas(SchemaStatus.broken))) {
            if (spinSql!(() => db.schemaApi.countMutantsInWorklist(id,
                    kinds)) >= schemataMutantsThreshold(schemaConf.minMutantsPerSchema.get, 0, 0)) {
                app.put(id);
            }
        }

        logger.trace("Found schematas: ", app.data).collectException;
        // random reorder to reduce the chance that multipe instances of
        // dextool use the same schema
        local.get!NextSchemata.schematas = app.data.randomCover.array;
        local.get!NextSchemata.totalSchematas = app.data.length;
    }

    void opCall(ref Coverage data) @trusted {
        import dextool.plugin.mutate.backend.test_mutant.coverage;

        auto tracked = spinSql!(() => db.getLatestTimeStampOfTestOrSut).orElse(SysTime.init);
        auto covTimeStamp = spinSql!(() => db.coverageApi.getCoverageTimeStamp).orElse(
                SysTime.init);

        if (tracked < covTimeStamp) {
            logger.info("Coverage information is up to date").collectException;
            return;
        } else {
            logger.infof("Coverage is out of date with SUT/tests (%s < %s)",
                    covTimeStamp, tracked).collectException;
        }

        try {
            auto driver = CoverageDriver(filesysIO, db, &runner, covConf,
                    conf.mutationCompile, conf.buildCmdTimeout);
            while (driver.isRunning) {
                driver.execute;
            }
            data.propagate = true;
            data.fatalError = driver.hasFatalError;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            data.fatalError = true;
        }

        if (data.fatalError)
            logger.warning("Error detected when trying to gather coverage information")
                .collectException;
    }

    void opCall(PropagateCoverage data) {
        void propagate() @trusted {
            auto trans = db.transaction;

            auto noCov = db.coverageApi.getNotCoveredMutants;
            foreach (id; noCov)
                db.mutantApi.update(id, Mutation.Status.noCoverage, ExitStatus(0));
            db.worklistApi.remove(Mutation.Status.noCoverage);

            trans.commit;
            logger.infof("Marked %s mutants as alive because they where not covered by any test",
                    noCov.length);
        }

        spinSql!(() => propagate);
    }

    void saveTestResult(MutationTestResult[] results) @safe nothrow {
        import dextool.plugin.mutate.backend.test_mutant.common_actors : GetMutantsLeft,
            UnknownMutantTested;

        foreach (a; results.filter!(a => a.status == Mutation.Status.alive)) {
            stopCheck.incrAliveMutants;
        }

        try {
            foreach (result; results)
                send(dbSave, result, timeoutFsm);
            send(stat, UnknownMutantTested.init, cast(long) results.length);
        } catch (Exception e) {
            logger.warning("Failed to send the result to the database: ", e.msg).collectException;
        }

        try {
            auto self = scopedActor;
            self.request(stat, delay(2.dur!"msecs")).send(GetMutantsLeft.init).then((long x) {
                logger.infof("%s mutants left to test.", x).collectException;
            });
        } catch (Exception e) {
            // just ignoring a slow answer
        }
    }

    void saveTestBinaryDb(ref TestBinaryDb testBinaryDb) @safe nothrow {
        import dextool.plugin.mutate.backend.database.type : ChecksumTestCmdMutated;

        spinSql!(() @trusted {
            auto t = db.transaction;
            foreach (a; testBinaryDb.added.byKeyValue) {
                db.testCmdApi.add(ChecksumTestCmdMutated(a.key), a.value);
            }
            // magic number. about 10 Mbyte in the database (8+8+8)*20000
            db.testCmdApi.trimMutated(200000);
            t.commit;
        });

        testBinaryDb.clearAdded;
    }
}

private:

/** A schemata must have at least this many mutants that have the status unknown
 * for it to be cost efficient to use schemata.
 *
 * The weights dynamically adjust with how many of the schemas that has failed
 * to compile.
 *
 * Params:
 *  checkSchemata = if the user has activated check_schemata that run all test cases before the schemata is used.
 */
long schemataMutantsThreshold(const long minThreshold, const long invalidSchematas,
        const long totalSchematas) @safe pure nothrow @nogc {
    // "10" is a magic number that felt good but not too conservative. A future
    // improvement is to instead base it on the ratio between compilation time
    // and test suite execution time.
    if (totalSchematas > 0)
        return cast(long)(minThreshold + 10.0 * (
                cast(double) invalidSchematas / cast(double) totalSchematas));
    return cast(long) minThreshold;
}

/** Compare the old test cases with those that have been found this run.
 *
 * TODO: the side effect that this function print to the console is NOT good.
 */
bool hasNewTestCases(ref Set!string old_tcs, ref Set!string found_tcs) @safe nothrow {
    bool rval;

    auto new_tcs = found_tcs.setDifference(old_tcs);
    foreach (tc; new_tcs.toRange) {
        logger.info(!rval, "Found new test case(s):").collectException;
        logger.infof("%s", tc).collectException;
        rval = true;
    }

    return rval;
}

/** Compare old and new test cases to print those that have been removed.
 */
void printDroppedTestCases(ref Set!string old_tcs, ref Set!string changed_tcs) @safe nothrow {
    auto diff = old_tcs.setDifference(changed_tcs);
    auto removed = diff.toArray;

    logger.info(removed.length != 0, "Detected test cases that has been removed:").collectException;
    foreach (tc; removed) {
        logger.infof("%s", tc).collectException;
    }
}

/// Returns: true if all tests cases have unique identifiers
void warnIfConflictingTestCaseIdentifiers(TestCase[] found_tcs) @safe nothrow {
    Set!TestCase checked;
    bool conflict;

    foreach (tc; found_tcs) {
        if (checked.contains(tc)) {
            logger.info(!conflict,
                    "Found test cases that do not have global, unique identifiers")
                .collectException;
            logger.info(!conflict,
                    "This make the report of test cases that has killed zero mutants unreliable")
                .collectException;
            logger.info("%s", tc).collectException;
            conflict = true;
        }
    }
}

private:

import dextool.plugin.mutate.backend.database : dbOpenTimeout;

ulong toMinMemory(double percentageOfTotal) {
    import core.sys.posix.unistd : _SC_PHYS_PAGES, _SC_PAGESIZE, sysconf;

    return cast(ulong)((1.0 - (percentageOfTotal / 100.0)) * sysconf(
            _SC_PHYS_PAGES) * sysconf(_SC_PAGESIZE));
}

auto spawnDbSaveActor(DbSaveActor.Impl self, AbsolutePath dbPath) @trusted {
    import dextool.plugin.mutate.backend.test_mutant.common_actors : Init, IsDone;

    static struct State {
        Database db;
    }

    auto st = tuple!("self", "state")(self, refCounted(State.init));
    alias Ctx = typeof(st);

    static void init_(ref Ctx ctx, Init _, AbsolutePath dbPath) nothrow {
        try {
            ctx.state.get.db = spinSql!(() => Database.make(dbPath), silentLog)(dbOpenTimeout);
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            ctx.self.shutdown;
        }
    }

    static void save2(ref Ctx ctx, MutationTestResult result, TimeoutFsm timeoutFsm) @safe nothrow {
        try {
            send(ctx.self, result, timeoutFsm.output.iter);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    static void save(ref Ctx ctx, MutationTestResult result, long timeoutIter) @safe nothrow {
        void statusUpdate(MutationTestResult result) @safe {
            import dextool.plugin.mutate.backend.test_mutant.timeout : updateMutantStatus;

            updateMutantStatus(ctx.state.get.db, result.id, result.status,
                    result.exitStatus, timeoutIter);
            ctx.state.get.db.mutantApi.update(result.id, result.profile);
            foreach (a; result.testCmds)
                ctx.state.get.db.mutantApi.relate(result.id, a.toString);
            ctx.state.get.db.testCaseApi.updateMutationTestCases(result.id, result.testCases);
            ctx.state.get.db.worklistApi.remove(result.id);
        }

        spinSql!(() @trusted {
            auto t = ctx.state.get.db.transaction;
            statusUpdate(result);
            t.commit;
        });
    }

    static bool isDone(IsDone _) @safe nothrow {
        // the mailbox is a FIFO queue. all results have been saved if this returns true.
        return true;
    }

    self.name = "db";
    send(self, Init.init, dbPath);
    return impl(self, &init_, st, &save, st, &save2, st, &isDone);
}

auto spawnStatActor(StatActor.Impl self, AbsolutePath dbPath) @trusted {
    import dextool.plugin.mutate.backend.test_mutant.common_actors : Init,
        GetMutantsLeft, UnknownMutantTested, Tick, ForceUpdate;

    static struct State {
        Database db;
        long worklistCount;
    }

    auto st = tuple!("self", "state")(self, refCounted(State.init));
    alias Ctx = typeof(st);

    static void init_(ref Ctx ctx, Init _, AbsolutePath dbPath) nothrow {
        try {
            ctx.state.get.db = spinSql!(() => Database.make(dbPath), silentLog)(dbOpenTimeout);
            send(ctx.self, Tick.init);
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            ctx.self.shutdown;
        }
    }

    static void tick(ref Ctx ctx, Tick _) @safe nothrow {
        try {
            ctx.state.get.worklistCount = spinSql!(() => ctx.state.get.db.worklistApi.getCount,
                    logger.trace);
            delayedSend(ctx.self, delay(30.dur!"seconds"), Tick.init);
        } catch (Exception e) {
            logger.error(e.msg).collectException;
        }
    }

    static void unknownTested(ref Ctx ctx, UnknownMutantTested _, long tested) @safe nothrow {
        ctx.state.get.worklistCount = max(0, ctx.state.get.worklistCount - tested);
    }

    static void forceUpdate(ref Ctx ctx, ForceUpdate _) @safe nothrow {
        tick(ctx, Tick.init);
    }

    static long left(ref Ctx ctx, GetMutantsLeft _) @safe nothrow {
        return ctx.state.get.worklistCount;
    }

    self.name = "stat";
    send(self, Init.init, dbPath);
    return impl(self, &init_, st, &tick, st, &left, st, &forceUpdate, st, &unknownTested, st);
}
