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
import std.algorithm : map;
import std.array : empty, array, appender;
import std.datetime : SysTime, Clock;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.exception : collectException;
import std.format : format;
import std.random : randomCover;
import std.typecons : Nullable, Tuple, Yes;

import blob_model : Blob;
import my.fsm : Fsm, next, act, get, TypeDataMap;
import my.named_type;
import my.optional;
import my.set;
import proc : DrainElement;
import sumtype;
static import my.fsm;

import dextool.plugin.mutate.backend.database : Database, MutationEntry,
    NextMutationEntry, spinSql, TestFile;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.test_mutant.common;
import dextool.plugin.mutate.backend.test_mutant.test_cmd_runner : TestRunner,
    findExecutables, TestRunResult = TestResult;
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
    }

    private InternalData data;

    auto config(ConfigMutationTest c) nothrow {
        data.config = c;
        return this;
    }

    auto mutations(MutationKind[] v) nothrow {
        import dextool.plugin.mutate.backend.utility : toInternal;

        logger.infof("mutation operators: %(%s, %)", v).collectException;

        data.kinds = toInternal(v);
        return this;
    }

    ExitStatusType run(const AbsolutePath dbPath, FilesysIO fio) @trusted {
        try {
            auto db = Database.make(dbPath);
            return internalRun(db, fio);
        } catch (Exception e) {
            logger.error(e.msg).collectException;
        }

        return ExitStatusType.Errors;
    }

    private ExitStatusType internalRun(ref Database db, FilesysIO fio) {
        // trusted because the lifetime of the database is guaranteed to outlive any instances in this scope
        auto db_ref = () @trusted { return &db; }();

        auto cleanup = new AutoCleanup;
        scope (exit)
            cleanup.cleanup;

        auto driver_data = DriverData(db_ref, fio, data.kinds, cleanup, data.config);

        auto test_driver = TestDriver(driver_data);

        while (test_driver.isRunning) {
            test_driver.execute;
        }

        return test_driver.status;
    }
}

struct DriverData {
    Database* db;
    FilesysIO filesysIO;
    Mutation.Kind[] kinds;
    AutoCleanup autoCleanup;
    ConfigMutationTest conf;
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
        auto res = runner.run;
        return Rval(res, sw.peek);
    }

    static void print(DrainElement[] data) @trusted {
        import std.stdio : stdout, write;

        foreach (l; data) {
            write(l.byUTF8);
        }
        stdout.flush;
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
            case Status.error:
                failed = true;
                print(res.result.output);
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
    import dextool.plugin.mutate.backend.database : Schemata, SchemataId, MutationStatusId;
    import dextool.plugin.mutate.backend.test_mutant.source_mutant : MutationTestDriver;
    import dextool.plugin.mutate.backend.test_mutant.timeout : calculateTimeout, TimeoutFsm;
    import dextool.plugin.mutate.backend.report.analyzers : EstimateScore;

    /// Runs the test commands.
    TestRunner runner;

    ///
    TestCaseAnalyzer testCaseAnalyzer;

    static struct Global {
        DriverData data;

        TimeoutFsm timeoutFsm;

        /// The time it takes to execute the test suite when no mutant is injected.
        Duration testSuiteRuntime;

        /// the next mutant to test, if there are any.
        MutationEntry nextMutant;

        // when the user manually configure the timeout it means that the
        // timeout algorithm should not be used.
        bool hardcodedTimeout;

        /// Max time to run the mutation testing for.
        SysTime maxRuntime;

        /// Test commands to execute.
        ShellCommand[] testCmds;

        /// mutation score estimation
        EstimateScore estimate;
    }

    static struct UpdateTimeoutData {
        long lastTimeoutIter;
    }

    static struct None {
    }

    static struct Initialize {
    }

    static struct PullRequest {
    }

    static struct PullRequestData {
        import dextool.plugin.mutate.type : TestConstraint;

        TestConstraint constraint;
        long seed;
    }

    static struct SanityCheck {
        bool sanityCheckFailed;
    }

    static struct AnalyzeTestCmdForTestCase {
        TestCase[] foundTestCases;
    }

    static struct UpdateAndResetAliveMutants {
        TestCase[] foundTestCases;
    }

    static struct ResetOldMutant {
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

    static struct ParseStdin {
    }

    static struct PreCompileSut {
        bool compilationError;
    }

    static struct FindTestCmds {
    }

    static struct ChooseMode {
    }

    static struct MeasureTestSuite {
        bool unreliableTestSuite;
    }

    static struct MutationTest {
        bool mutationError;
        MutationTestResult[] result;
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
        /// stop mutation testing because the last schema has been used and the
        /// user has configured that the testing should stop now.
        NamedType!(bool, Tag!"StopTesting", bool.init, TagStringable, ImplicitConvertable) stop;
    }

    static struct PreSchemataData {
        Schemata schemata;
    }

    static struct PreSchemata {
        bool error;
        SchemataId id;
    }

    static struct SanityCheckSchemata {
        SchemataId id;
        bool passed;
    }

    static struct SchemataTestData {
        Duration compileTime;
    }

    static struct SchemataTest {
        SchemataId id;
        MutationTestResult[] result;
    }

    static struct SchemataTestResult {
        SchemataId id;
        MutationTestResult[] result;
    }

    static struct SchemataRestore {
        bool error;
    }

    static struct SchemataRestoreData {
        static struct Original {
            AbsolutePath path;
            Blob original;
        }

        Original[] original;
    }

    static struct SchemataPruneUsed {
    }

    static struct Done {
    }

    static struct Error {
    }

    static struct UpdateTimeout {
    }

    static struct NextPullRequestMutant {
        NamedType!(bool, Tag!"NoUnknown", bool.init, TagStringable, ImplicitConvertable) noUnknownMutantsLeft;
    }

    static struct NextPullRequestMutantData {
        import dextool.plugin.mutate.backend.database : MutationStatusId;

        MutationStatusId[] mutants;

        /// If set then stop after this many alive are found.
        Nullable!int maxAlive;
        /// number of alive mutants that has been found.
        int alive;
    }

    static struct NextMutant {
        NamedType!(bool, Tag!"NoUnknown", bool.init, TagStringable, ImplicitConvertable) noUnknownMutantsLeft;
    }

    static struct HandleTestResult {
        MutationTestResult[] result;
    }

    static struct CheckRuntime {
        bool reachedMax;
    }

    static struct LoadSchematas {
    }

    static struct OverloadCheck {
        bool halt;
        bool sleep;
    }

    static struct Stop {
    }

    alias Fsm = my.fsm.Fsm!(None, Initialize, SanityCheck,
            AnalyzeTestCmdForTestCase, UpdateAndResetAliveMutants, ResetOldMutant,
            Cleanup, CheckMutantsLeft, PreCompileSut, MeasureTestSuite, NextMutant,
            MutationTest, HandleTestResult, CheckTimeout, Done, Error,
            UpdateTimeout, CheckRuntime, PullRequest, NextPullRequestMutant, ParseStdin,
            FindTestCmds, ChooseMode, NextSchemata, PreSchemata, SchemataTest,
            SchemataTestResult, SchemataRestore, LoadSchematas,
            SanityCheckSchemata, SchemataPruneUsed, Stop, SaveMutationScore, OverloadCheck);
    alias LocalStateDataT = Tuple!(UpdateTimeoutData, NextPullRequestMutantData, PullRequestData, ResetOldMutantData,
            SchemataRestoreData, PreSchemataData, NextSchemataData, SchemataTestData);

    private {
        Fsm fsm;
        Global global;
        TypeDataMap!(LocalStateDataT, UpdateTimeout, NextPullRequestMutant, PullRequest,
                ResetOldMutant, SchemataRestore, PreSchemata, NextSchemata, SchemataTest) local;
        bool isRunning_ = true;
        bool isDone = false;
    }

    this(DriverData data) {
        this.global = Global(data);
        this.global.timeoutFsm = TimeoutFsm(data.kinds);
        this.global.hardcodedTimeout = !global.data.conf.mutationTesterRuntime.isNull;
        local.get!PullRequest.constraint = global.data.conf.constraint;
        local.get!PullRequest.seed = global.data.conf.pullRequestSeed;
        local.get!NextPullRequestMutant.maxAlive = global.data.conf.maxAlive;
        local.get!ResetOldMutant.maxReset = global.data.conf.oldMutantsNr;
        local.get!ResetOldMutant.resetPercentage = global.data.conf.oldMutantPercentage;
        this.global.testCmds = global.data.conf.mutationTester;

        this.runner.useEarlyStop(global.data.conf.useEarlyTestCmdStop);
        this.runner = TestRunner.make(global.data.conf.testPoolSize);
        this.runner.useEarlyStop(global.data.conf.useEarlyTestCmdStop);
        // using an unreasonable timeout to make it possible to analyze for
        // test cases and measure the test suite.
        this.runner.timeout = 999.dur!"hours";
        this.runner.put(data.conf.mutationTester);

        // TODO: allow a user, as is for test_cmd, to specify an array of
        // external analyzers.
        this.testCaseAnalyzer = TestCaseAnalyzer(global.data.conf.mutationTestCaseBuiltin,
                global.data.conf.mutationTestCaseAnalyze, global.data.autoCleanup);
    }

    static void execute_(ref TestDriver self) @trusted {
        // see test_mutant/basis.md and figures/test_mutant_fsm.pu for a
        // graphical view of the state machine.

        self.fsm.next!((None a) => fsm(Initialize.init),
                (Initialize a) => fsm(SanityCheck.init), (SanityCheck a) {
            if (a.sanityCheckFailed)
                return fsm(Error.init);
            if (self.global.data.conf.unifiedDiffFromStdin)
                return fsm(ParseStdin.init);
            return fsm(PreCompileSut.init);
        }, (ParseStdin a) => fsm(PreCompileSut.init), (AnalyzeTestCmdForTestCase a) => fsm(
                UpdateAndResetAliveMutants(a.foundTestCases)),
                (UpdateAndResetAliveMutants a) => fsm(CheckMutantsLeft.init),
                (ResetOldMutant a) => fsm(UpdateTimeout.init), (Cleanup a) {
            if (self.local.get!PullRequest.constraint.empty)
                return fsm(NextSchemata.init);
            return fsm(NextPullRequestMutant.init);
        }, (CheckMutantsLeft a) {
            if (a.allMutantsTested)
                return fsm(SaveMutationScore.init);
            return fsm(MeasureTestSuite.init);
        }, (SaveMutationScore a) {
            if (self.global.data.conf.onOldMutants == ConfigMutationTest.OldMutant.nothing)
                return fsm(Done.init);
            return fsm(MeasureTestSuite.init);
        }, (PreCompileSut a) {
            if (a.compilationError)
                return fsm(Error.init);
            if (self.global.data.conf.testCommandDir.empty)
                return fsm(ChooseMode.init);
            return fsm(FindTestCmds.init);
        }, (FindTestCmds a) { return fsm(ChooseMode.init); }, (ChooseMode a) {
            if (!self.local.get!PullRequest.constraint.empty)
                return fsm(PullRequest.init);
            if (!self.global.data.conf.mutationTestCaseAnalyze.empty
                || !self.global.data.conf.mutationTestCaseBuiltin.empty)
                return fsm(AnalyzeTestCmdForTestCase.init);
            return fsm(CheckMutantsLeft.init);
        }, (PullRequest a) => fsm(CheckMutantsLeft.init), (MeasureTestSuite a) {
            if (a.unreliableTestSuite)
                return fsm(Error.init);
            return fsm(LoadSchematas.init);
        }, (LoadSchematas a) => fsm(ResetOldMutant.init), (NextPullRequestMutant a) {
            if (a.noUnknownMutantsLeft)
                return fsm(Done.init);
            return fsm(MutationTest.init);
        }, (NextSchemata a) {
            if (a.hasSchema)
                return fsm(PreSchemata.init);
            if (a.stop)
                return fsm(Done.init);
            return fsm(NextMutant.init);
        }, (PreSchemata a) {
            if (a.error)
                return fsm(Error.init);
            return fsm(SanityCheckSchemata(a.id));
        }, (SanityCheckSchemata a) {
            if (a.passed)
                return fsm(SchemataTest(a.id));
            return fsm(SchemataRestore.init);
        }, (SchemataTest a) { return fsm(SchemataTestResult(a.id, a.result)); },
                (SchemataTestResult a) => fsm(SchemataRestore.init), (SchemataRestore a) {
            if (a.error)
                return fsm(Error.init);
            return fsm(CheckRuntime.init);
        }, (NextMutant a) {
            if (a.noUnknownMutantsLeft)
                return fsm(CheckTimeout.init);
            return fsm(MutationTest.init);
        }, (UpdateTimeout a) => fsm(OverloadCheck.init), (OverloadCheck a) {
            if (a.halt)
                return fsm(Done.init);
            if (a.sleep)
                return fsm(CheckRuntime.init);
            return fsm(Cleanup.init);
        }, (MutationTest a) {
            if (a.mutationError)
                return fsm(Error.init);
            return fsm(HandleTestResult(a.result));
        }, (HandleTestResult a) => fsm(CheckRuntime.init), (CheckRuntime a) {
            if (a.reachedMax)
                return fsm(Done.init);
            return fsm(UpdateTimeout.init);
        }, (CheckTimeout a) {
            if (a.timeoutUnchanged)
                return fsm(Done.init);
            return fsm(UpdateTimeout.init);
        }, (SchemataPruneUsed a) => fsm(Stop.init),
                (Done a) => fsm(SchemataPruneUsed.init),
                (Error a) => fsm(Stop.init), (Stop a) => fsm(a));

        debug logger.trace("state: ", self.fsm.logNext);
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

    void opCall(Initialize data) {
        logger.info("Initializing worklist").collectException;
        global.maxRuntime = Clock.currTime + global.data.conf.maxRuntime;
        spinSql!(() {
            global.data.db.updateWorklist(global.data.kinds, Mutation.Status.unknown);
        });
    }

    void opCall(Stop data) {
        isRunning_ = false;
    }

    void opCall(Done data) {
        global.data.autoCleanup.cleanup;
        logger.info("Done!").collectException;
        isDone = true;
    }

    void opCall(Error data) {
        global.data.autoCleanup.cleanup;
    }

    void opCall(ref SanityCheck data) {
        import std.path : buildPath;
        import colorlog : color, Color;
        import dextool.plugin.mutate.backend.utility : checksum, Checksum;

        logger.info("Checking that the file(s) on the filesystem match the database")
            .collectException;

        auto failed = appender!(string[])();
        foreach (file; spinSql!(() { return global.data.db.getFiles; })) {
            auto db_checksum = spinSql!(() {
                return global.data.db.getFileChecksum(file);
            });

            try {
                auto abs_f = AbsolutePath(buildPath(global.data.filesysIO.getOutputDir, file));
                auto f_checksum = checksum(global.data.filesysIO.makeInput(abs_f).content[]);
                if (db_checksum != f_checksum) {
                    failed.put(abs_f);
                }
            } catch (Exception e) {
                // assume it is a problem reading the file or something like that.
                failed.put(file);
                logger.warningf("%s: %s", file, e.msg).collectException;
            }
        }

        data.sanityCheckFailed = failed.data.length != 0;

        if (data.sanityCheckFailed) {
            logger.error("Detected that file(s) has changed since last analyze where done")
                .collectException;
            logger.error("Either restore the file(s) or rerun the analyze").collectException;
            foreach (f; failed.data) {
                logger.info(f).collectException;
            }
        } else {
            logger.info("Ok".color(Color.green)).collectException;
        }
    }

    void opCall(ref OverloadCheck data) {
        if (global.data.conf.loadBehavior == ConfigMutationTest.LoadBehavior.nothing) {
            return;
        }

        const load15 = () @trusted {
            double[3] load;
            const nr = getloadavg(&load[0], 3);
            if (nr <= 0 || nr > load.length) {
                return 0.0;
            }
            return load[nr - 1];
        }();

        const isOverloaded = load15 > global.data.conf.loadThreshold.get;

        if (isOverloaded) {
            logger.infof("Detected overload (%s > %s).", load15,
                    global.data.conf.loadThreshold.get).collectException;
        }

        final switch (global.data.conf.loadBehavior) with (ConfigMutationTest.LoadBehavior) {
        case nothing:
            break;
        case slowdown:
            const sleepFor = 30.dur!"seconds";
            data.sleep = isOverloaded;
            if (isOverloaded) {
                logger.infof("Sleeping %s", sleepFor).collectException;
                import core.thread : Thread;

                () @trusted { Thread.sleep(sleepFor); }();
            }
            break;
        case halt:
            logger.warning(isOverloaded, "Halting").collectException;
            data.halt = isOverloaded;
            break;
        }
    }

    void opCall(ParseStdin data) {
        import dextool.plugin.mutate.backend.diff_parser : diffFromStdin;
        import dextool.plugin.mutate.type : Line;

        try {
            auto constraint = local.get!PullRequest.constraint;
            foreach (pkv; diffFromStdin.toRange(global.data.filesysIO.getOutputDir)) {
                constraint.value[pkv.key] ~= pkv.value.toRange.map!(a => Line(a)).array;
            }
            local.get!PullRequest.constraint = constraint;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    void opCall(ref AnalyzeTestCmdForTestCase data) {
        import std.datetime.stopwatch : StopWatch;
        import dextool.plugin.mutate.backend.type : TestCase;

        TestCase[] found;
        try {
            auto res = runTester(runner);
            auto analyze = testCaseAnalyzer.analyze(res.output, Yes.allFound);

            analyze.match!((TestCaseAnalyzer.Success a) { found = a.found; },
                    (TestCaseAnalyzer.Unstable a) {
                logger.warningf("Unstable test cases found: [%-(%s, %)]", a.unstable);
                found = a.found;
            }, (TestCaseAnalyzer.Failed a) {
                logger.warning("The parser that analyze the output for test case(s) failed");
            });
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }

        warnIfConflictingTestCaseIdentifiers(found);
        data.foundTestCases = found;
    }

    void opCall(UpdateAndResetAliveMutants data) {
        import std.traits : EnumMembers;

        // the test cases before anything has potentially changed.
        auto old_tcs = spinSql!(() {
            Set!string old_tcs;
            foreach (tc; global.data.db.getDetectedTestCases) {
                old_tcs.add(tc.name);
            }
            return old_tcs;
        });

        void transaction() @safe {
            final switch (global.data.conf.onRemovedTestCases) with (
                ConfigMutationTest.RemovedTestCases) {
            case doNothing:
                global.data.db.addDetectedTestCases(data.foundTestCases);
                break;
            case remove:
                bool update;
                // change all mutants which, if a test case is removed, no
                // longer has a test case that kills it to unknown status
                foreach (id; global.data.db.setDetectedTestCases(data.foundTestCases)) {
                    if (!global.data.db.hasTestCases(id)) {
                        update = true;
                        global.data.db.updateMutationStatus(id,
                                Mutation.Status.unknown, ExitStatus(0));
                    }
                }
                if (update) {
                    global.data.db.updateWorklist(global.data.kinds, Mutation.Status.unknown);
                }
                break;
            }
        }

        auto found_tcs = spinSql!(() @trusted {
            auto tr = global.data.db.transaction;
            transaction();

            Set!string found_tcs;
            foreach (tc; global.data.db.getDetectedTestCases) {
                found_tcs.add(tc.name);
            }

            tr.commit;
            return found_tcs;
        });

        printDroppedTestCases(old_tcs, found_tcs);

        if (hasNewTestCases(old_tcs, found_tcs)
                && global.data.conf.onNewTestCases == ConfigMutationTest.NewTestCases.resetAlive) {
            logger.info("Adding alive mutants to worklist").collectException;
            spinSql!(() {
                global.data.db.updateWorklist(global.data.kinds, Mutation.Status.alive);
            });
        }
    }

    void opCall(ResetOldMutant data) {
        import dextool.plugin.mutate.backend.database.type;

        void printStatus(T0, T1)(T0 oldestMutant, T1 oldestTest) {
            logger.info("Tests last changed ", oldestTest).collectException;
            if (!oldestMutant.empty) {
                logger.info("The oldest mutant is ", oldestMutant[0].updated).collectException;
            }
        }

        if (global.data.conf.onOldMutants == ConfigMutationTest.OldMutant.nothing) {
            return;
        }
        if (spinSql!(() { return global.data.db.getWorklistCount; }) != 0) {
            // do not re-test any old mutants if there are still work to do in the worklist.
            return;
        }

        const oldestMutant = spinSql!(() => global.data.db.getOldestMutants(global.data.kinds, 1));
        const oldestTest = spinSql!(() => global.data.db.getOldestTestFile).orElse(
                TestFile.init).timeStamp;
        if (!oldestMutant.empty && oldestMutant[0].updated > oldestTest) {
            // only re-test old mutants if the tests has changed.
            logger.info("Mutation status is up to date with the test cases").collectException;
            printStatus(oldestMutant, oldestTest);
            return;
        } else {
            logger.info("Mutation status and test cases are out of sync").collectException;
            printStatus(oldestMutant, oldestTest);
        }

        const long testCnt = () {
            if (local.get!ResetOldMutant.resetPercentage.get == 0.0) {
                return local.get!ResetOldMutant.maxReset;
            }

            const total = spinSql!(() {
                return global.data.db.totalSrcMutants(global.data.kinds).count;
            });
            const rval = cast(long)(1 + total * local.get!ResetOldMutant.resetPercentage.get
                    / 100.0);
            return rval;
        }();

        auto oldest = spinSql!(() {
            return global.data.db.getOldestMutants(global.data.kinds, testCnt);
        });

        logger.infof("Adding %s old mutants to worklist", oldest.length).collectException;
        foreach (const old; oldest) {
            logger.info("Last updated ", old.updated).collectException;
            spinSql!(() { global.data.db.addToWorklist(old.id); });
        }
    }

    void opCall(Cleanup data) {
        global.data.autoCleanup.cleanup;
    }

    void opCall(ref CheckMutantsLeft data) {
        spinSql!(() { global.timeoutFsm.execute(*global.data.db); });

        data.allMutantsTested = global.timeoutFsm.output.done;

        if (global.timeoutFsm.output.done) {
            logger.info("All mutants are tested").collectException;
        }
    }

    void opCall(SaveMutationScore data) {
        import dextool.plugin.mutate.backend.database.type : MutationScore;
        import dextool.plugin.mutate.backend.report.analyzers : reportScore;

        const score = reportScore(*global.data.db, global.data.kinds).score;

        // 10000 mutation scores is only ~80kbyte. Should be enough entries
        // without taking up unresonable amount of space.
        spinSql!(() @trusted {
            auto t = global.data.db.transaction;
            global.data.db.putMutationScore(MutationScore(Clock.currTime,
                typeof(MutationScore.score)(score)));
            global.data.db.trimMutationScore(10000);
            t.commit;
        });
    }

    void opCall(ref PreCompileSut data) {
        import std.stdio : write;
        import colorlog : color, Color;
        import proc;

        logger.info("Checking the build command").collectException;
        compile(global.data.conf.mutationCompile, global.data.conf.buildCmdTimeout, true).match!(
                (Mutation.Status a) { data.compilationError = true; }, (bool success) {
            data.compilationError = !success;
        });
    }

    void opCall(FindTestCmds data) {
        auto cmds = appender!(ShellCommand[])();
        foreach (root; global.data.conf.testCommandDir) {
            try {
                cmds.put(findExecutables(root.AbsolutePath)
                        .map!(a => ShellCommand([a] ~ global.data.conf.testCommandDirFlag)));
            } catch (Exception e) {
                logger.warning(e.msg).collectException;
            }
        }

        if (!cmds.data.empty) {
            this.global.testCmds ~= cmds.data;
            this.runner.put(this.global.testCmds);
            logger.infof("Found test commands in %s:",
                    global.data.conf.testCommandDir).collectException;
            foreach (c; cmds.data) {
                logger.info(c).collectException;
            }
        }
    }

    void opCall(ChooseMode data) {
    }

    void opCall(PullRequest data) {
        import std.algorithm : sort;
        import std.random : Mt19937_64;
        import dextool.plugin.mutate.backend.database : MutationStatusId;
        import dextool.plugin.mutate.backend.type : SourceLoc;
        import my.set;

        Set!MutationStatusId mut_ids;

        foreach (kv; local.get!PullRequest.constraint.value.byKeyValue) {
            const file_id = spinSql!(() => global.data.db.getFileId(kv.key));
            if (file_id.isNull) {
                logger.infof("The file %s do not exist in the database. Skipping...",
                        kv.key).collectException;
                continue;
            }

            foreach (l; kv.value) {
                auto mutants = spinSql!(() {
                    return global.data.db.getMutationsOnLine(global.data.kinds,
                        file_id.get, SourceLoc(l.value, 0));
                });

                const pre_cnt = mut_ids.length;
                foreach (v; mutants)
                    mut_ids.add(v);

                logger.infof(mut_ids.length - pre_cnt > 0, "Found %s mutant(s) to test (%s:%s)",
                        mut_ids.length - pre_cnt, kv.key, l.value).collectException;
            }
        }

        logger.infof(!mut_ids.empty, "Found %s mutants in the diff",
                mut_ids.length).collectException;

        const seed = local.get!PullRequest.seed;
        logger.infof("Using random seed %s when choosing the mutants to test",
                seed).collectException;
        auto rng = Mt19937_64(seed);
        local.get!NextPullRequestMutant.mutants = mut_ids.toArray.sort.randomCover(rng).array;
        logger.trace("Test sequence ", local.get!NextPullRequestMutant.mutants).collectException;

        if (mut_ids.empty) {
            logger.warning("None of the locations specified with -L exists").collectException;
            logger.info("Available files are:").collectException;
            foreach (f; spinSql!(() => global.data.db.getFiles))
                logger.info(f).collectException;
        }
    }

    void opCall(ref MeasureTestSuite data) {
        import std.algorithm : max, sum;
        import dextool.plugin.mutate.backend.database.type : TestCmdRuntime;

        if (!global.data.conf.mutationTesterRuntime.isNull) {
            global.testSuiteRuntime = global.data.conf.mutationTesterRuntime.get;
            return;
        }

        logger.infof("Measuring the runtime of the test command(s):\n%(%s\n%)",
                global.testCmds).collectException;

        auto measures = spinSql!(() => global.data.db.getTestCmdRuntimes);

        const tester = () {
            try {
                // need to measure the test suite single threaded to get the "worst"
                // test case execution time because if multiple instances are running
                // on the same computer the available CPU resources are variable. This
                // reduces the number of mutants marked as timeout. Further
                // improvements in the future could be to check the loadavg and let it
                // affect the number of threads.
                runner.poolSize = 1;
                scope (exit)
                    runner.poolSize = global.data.conf.testPoolSize;
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

            // The sampling of the test suite become too unreliable when the timeout is <1s.
            // This is a quick and dirty fix.
            // A proper fix requires an update of the sampler in runTester.
            auto t = mean < 1.dur!"seconds" ? 1.dur!"seconds" : mean;
            logger.info("Test command runtime: ", t).collectException;
            global.testSuiteRuntime = t;

            spinSql!(() @trusted {
                auto t = global.data.db.transaction;
                global.data.db.setTestCmdRuntimes(measures);
                t.commit;
            });
        } else {
            data.unreliableTestSuite = true;
            logger.error("The test command is unreliable. It must return exit status '0' when no mutants are injected")
                .collectException;
        }
    }

    void opCall(ref MutationTest data) {
        auto p = () @trusted { return &runner; }();

        try {
            auto g = MutationTestDriver.Global(global.data.filesysIO,
                    global.data.db, global.nextMutant, p);
            auto driver = MutationTestDriver(g,
                    MutationTestDriver.TestMutantData(!(global.data.conf.mutationTestCaseAnalyze.empty
                        && global.data.conf.mutationTestCaseBuiltin.empty),
                        global.data.conf.mutationCompile, global.data.conf.buildCmdTimeout),
                    MutationTestDriver.TestCaseAnalyzeData(&testCaseAnalyzer));

            while (driver.isRunning) {
                driver.execute();
            }

            if (driver.stopBecauseError) {
                data.mutationError = true;
            } else {
                data.result = driver.result;
            }
        } catch (Exception e) {
            data.mutationError = true;
            logger.error(e.msg).collectException;
        }
    }

    void opCall(ref CheckTimeout data) {
        data.timeoutUnchanged = global.hardcodedTimeout || global.timeoutFsm.output.done;
    }

    void opCall(UpdateTimeout) {
        spinSql!(() { global.timeoutFsm.execute(*global.data.db); });

        const lastIter = local.get!UpdateTimeout.lastTimeoutIter;

        if (lastIter != global.timeoutFsm.output.iter) {
            logger.infof("Changed the timeout from %s to %s (iteration %s)",
                    calculateTimeout(lastIter, global.testSuiteRuntime),
                    calculateTimeout(global.timeoutFsm.output.iter, global.testSuiteRuntime),
                    global.timeoutFsm.output.iter).collectException;
            local.get!UpdateTimeout.lastTimeoutIter = global.timeoutFsm.output.iter;
        }

        runner.timeout = calculateTimeout(global.timeoutFsm.output.iter, global.testSuiteRuntime);
    }

    void opCall(ref NextPullRequestMutant data) {
        global.nextMutant = MutationEntry.init;
        data.noUnknownMutantsLeft.get = true;

        while (!local.get!NextPullRequestMutant.mutants.empty) {
            const id = local.get!NextPullRequestMutant.mutants[$ - 1];
            const status = spinSql!(() => global.data.db.getMutationStatus(id));

            if (status.isNull)
                continue;

            if (status.get == Mutation.Status.alive) {
                local.get!NextPullRequestMutant.alive++;
            }

            if (status.get != Mutation.Status.unknown) {
                local.get!NextPullRequestMutant.mutants
                    = local.get!NextPullRequestMutant.mutants[0 .. $ - 1];
                continue;
            }

            const info = spinSql!(() => global.data.db.getMutantsInfo(global.data.kinds, [
                        id
                    ]));
            if (info.empty)
                continue;

            global.nextMutant = spinSql!(() => global.data.db.getMutation(info[0].id));
            data.noUnknownMutantsLeft.get = false;
            break;
        }

        if (!local.get!NextPullRequestMutant.maxAlive.isNull) {
            const alive = local.get!NextPullRequestMutant.alive;
            const maxAlive = local.get!NextPullRequestMutant.maxAlive.get;
            logger.infof(alive > 0, "Found %s/%s alive mutants", alive, maxAlive).collectException;
            if (alive >= maxAlive) {
                data.noUnknownMutantsLeft.get = true;
            }
        }
    }

    void opCall(ref NextMutant data) {
        global.nextMutant = MutationEntry.init;

        auto next = spinSql!(() {
            return global.data.db.nextMutation(global.data.kinds, global.data.conf.mutationOrder);
        });

        data.noUnknownMutantsLeft.get = next.st == NextMutationEntry.Status.done;

        if (!next.entry.isNull) {
            global.nextMutant = next.entry.get;
        }
    }

    void opCall(HandleTestResult data) {
        saveTestResult(data.result);
    }

    void opCall(ref CheckRuntime data) {
        data.reachedMax = Clock.currTime > global.maxRuntime;
        if (data.reachedMax) {
            logger.infof("Max runtime of %s reached at %s",
                    global.data.conf.maxRuntime, global.maxRuntime).collectException;
        }
    }

    void opCall(ref NextSchemata data) {
        auto schematas = local.get!NextSchemata.schematas;

        const threshold = schemataMutantsThreshold(global.data.conf.sanityCheckSchemata,
                local.get!NextSchemata.invalidSchematas, local.get!NextSchemata.totalSchematas);

        while (!schematas.empty && !data.hasSchema) {
            const id = schematas[0];
            schematas = schematas[1 .. $];
            const mutants = spinSql!(() {
                return global.data.db.schemataMutantsCount(id, global.data.kinds);
            });

            logger.infof("Schema %s has %s mutants (threshold %s)", id.get,
                    mutants, threshold).collectException;

            if (mutants >= threshold) {
                auto schema = spinSql!(() {
                    return global.data.db.getSchemata(id);
                });
                if (!schema.isNull) {
                    local.get!PreSchemata.schemata = schema;
                    logger.infof("Use schema %s (%s left)", id.get,
                            schematas.length).collectException;
                    data.hasSchema.get = true;
                }
            }
        }

        local.get!NextSchemata.schematas = schematas;

        data.stop.get = !data.hasSchema && global.data.conf.stopAfterLastSchema;
    }

    void opCall(ref PreSchemata data) {
        import std.algorithm : filter;
        import dextool.plugin.mutate.backend.database.type : SchemataFragment;

        auto sw = StopWatch(AutoStart.yes);
        // also accumulate all the time spent on failing to compile schematan.
        scope (exit)
            local.get!SchemataTest.compileTime = local.get!SchemataTest.compileTime + sw.peek;

        auto schemata = local.get!PreSchemata.schemata;
        data.id = schemata.id;
        local.get!PreSchemata = PreSchemataData.init;

        Blob makeSchemata(Blob original, SchemataFragment[] fragments) {
            import blob_model;

            Edit[] edits;
            foreach (a; fragments) {
                edits ~= new Edit(Interval(a.offset.begin, a.offset.end), a.text);
            }
            auto m = merge(original, edits);
            return change(new Blob(original.uri, original.content), m.edits);
        }

        SchemataFragment[] fragments(Path p) {
            return schemata.fragments.filter!(a => a.file == p).array;
        }

        SchemataRestoreData.Original[] orgs;
        try {
            logger.info("Injecting the schemata in:");
            auto files = schemata.fragments.map!(a => a.file).toSet;
            foreach (f; files.toRange) {
                const absf = global.data.filesysIO.toAbsoluteRoot(f);
                logger.info(absf);

                orgs ~= SchemataRestoreData.Original(absf, global.data.filesysIO.makeInput(absf));

                // writing the schemata.
                auto s = makeSchemata(orgs[$ - 1].original, fragments(f));
                global.data.filesysIO.makeOutput(absf).write(s);

                if (global.data.conf.logSchemata) {
                    global.data.filesysIO.makeOutput(AbsolutePath(format!"%s.%s.schema"(absf,
                            schemata.id).Path)).write(s);
                }
            }
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            data.error = true;
        }
        local.get!SchemataRestore.original = orgs;
    }

    void opCall(ref SchemataTest data) {
        import dextool.plugin.mutate.backend.test_mutant.schemata;

        // add the database access as "compile time"
        auto sw = StopWatch(AutoStart.yes);

        auto mutants = spinSql!(() {
            return global.data.db.getSchemataMutants(data.id, global.data.kinds);
        });

        try {
            auto driver = SchemataTestDriver(global.data.filesysIO, &runner, global.data.db,
                    &testCaseAnalyzer, mutants, local.get!SchemataTest.compileTime + sw.peek);
            local.get!SchemataTest.compileTime = Duration.zero;

            while (driver.isRunning) {
                driver.execute;
            }
            data.result = driver.result;
        } catch (Exception e) {
            logger.info(e.msg).collectException;
            logger.warning("Failed executing schemata ", data.id).collectException;
        }
    }

    void opCall(SchemataTestResult data) {
        saveTestResult(data.result);

        // only remove schemas that are of no further use.
        bool remove = true;
        foreach (a; data.result) {
            final switch (a.status) with (Mutation.Status) {
            case unknown:
                goto case;
            case alive:
                remove = false;
                break;
            case killed:
                goto case;
            case timeout:
                goto case;
            case killedByCompiler:
                break;
            }
        }

        if (remove) {
            spinSql!(() { global.data.db.markUsed(data.id); });
        }
    }

    void opCall(ref SchemataRestore data) {
        foreach (o; local.get!SchemataRestore.original) {
            try {
                global.data.filesysIO.makeOutput(o.path).write(o.original.content);
            } catch (Exception e) {
                logger.error(e.msg).collectException;
                data.error = true;
            }
        }
        local.get!SchemataRestore.original = null;
    }

    void opCall(SchemataPruneUsed data) {
        try {
            const removed = global.data.db.pruneUsedSchemas;

            if (removed != 0) {
                logger.infof("Removed %s schemas from the database", removed);
                // vacuum the database because schemas take up a significant
                // amount of space.
                global.data.db.vacuum;
            }
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    void opCall(LoadSchematas data) {
        if (!global.data.conf.useSchemata) {
            return;
        }

        auto app = appender!(SchemataId[])();
        foreach (id; spinSql!(() { return global.data.db.getSchematas(); })) {
            if (spinSql!(() {
                    return global.data.db.schemataMutantsCount(id, global.data.kinds);
                }) >= schemataMutantsThreshold(global.data.conf.sanityCheckSchemata, 0, 0)) {
                app.put(id);
            }
        }

        logger.trace("Found schematas: ", app.data).collectException;
        // random reorder to reduce the chance that multipe instances of
        // dextool use the same schema
        local.get!NextSchemata.schematas = app.data.randomCover.array;
        local.get!NextSchemata.totalSchematas = app.data.length;
    }

    void opCall(ref SanityCheckSchemata data) {
        import colorlog;

        auto sw = StopWatch(AutoStart.yes);
        // also accumulate all the time spent on failing to compile schematan.
        scope (exit)
            local.get!SchemataTest.compileTime = local.get!SchemataTest.compileTime + sw.peek;

        logger.infof("Compile schema %s", data.id.get).collectException;

        if (global.data.conf.logSchemata) {
            const kinds = spinSql!(() {
                return global.data.db.getSchemataKinds(data.id);
            });
            if (!local.get!SchemataRestore.original.empty) {
                auto p = local.get!SchemataRestore.original[$ - 1].path;
                try {
                    global.data.filesysIO.makeOutput(AbsolutePath(format!"%s.%s.kinds.schema"(p,
                            data.id).Path)).write(format("%s", kinds));
                } catch (Exception e) {
                    logger.warning(e.msg).collectException;
                }
            }
        }

        bool successCompile;
        compile(global.data.conf.mutationCompile,
                global.data.conf.buildCmdTimeout, global.data.conf.logSchemata).match!(
                (Mutation.Status a) {}, (bool success) {
            successCompile = success;
        });

        if (!successCompile) {
            logger.info("Skipping schema because it failed to compile".color(Color.yellow))
                .collectException;
            spinSql!(() { global.data.db.markUsed(data.id); });
            local.get!NextSchemata.invalidSchematas++;
            return;
        }

        logger.info("Ok".color(Color.green)).collectException;

        if (!global.data.conf.sanityCheckSchemata) {
            data.passed = true;
            return;
        }

        try {
            logger.info("Sanity check of the generated schemata");
            auto res = runner.run;
            data.passed = res.status == TestRunResult.Status.passed;
            if (!data.passed) {
                local.get!NextSchemata.invalidSchematas++;
                debug logger.tracef("%(%s%)", res.output.map!(a => a.byUTF8));
            }
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }

        if (data.passed) {
            logger.info("Ok".color(Color.green)).collectException;
        } else {
            logger.info("Skipping saving the result of running the schemata because the test suite failed".color(
                    Color.yellow)).collectException;
            spinSql!(() { global.data.db.markUsed(data.id); });
        }
    }

    void saveTestResult(MutationTestResult[] results) @safe nothrow {
        void statusUpdate(MutationTestResult result) @safe {
            import dextool.plugin.mutate.backend.test_mutant.timeout : updateMutantStatus;

            const cnt_action = () {
                if (result.status == Mutation.Status.alive)
                    return Database.CntAction.incr;
                return Database.CntAction.reset;
            }();

            global.estimate.update(result.status);

            updateMutantStatus(*global.data.db, result.id, result.status,
                    result.exitStatus, global.timeoutFsm.output.iter);
            global.data.db.updateMutation(result.id, cnt_action);
            global.data.db.updateMutation(result.id, result.profile);
            global.data.db.updateMutationTestCases(result.id, result.testCases);
            global.data.db.removeFromWorklist(result.id);
        }

        spinSql!(() @trusted {
            auto t = global.data.db.transaction;
            foreach (a; results) {
                statusUpdate(a);
            }
            t.commit;
        });

        const left = spinSql!(() { return global.data.db.getWorklistCount; });
        logger.infof("%s mutants left to test. Estimated mutation score %.3s (error %.3s)", left,
                global.estimate.value.get, global.estimate.error.get).collectException;
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
long schemataMutantsThreshold(bool checkSchemata, long invalidSchematas, long totalSchematas) @safe pure nothrow @nogc {
    double f = checkSchemata ? 3 : 2;
    // "10" is a magic number that felt good but not too conservative. A future
    // improvement is to instead base it on the ratio between compilation time
    // and test suite execution time.
    if (totalSchematas > 0)
        f += 10.0 * (cast(double) invalidSchematas / cast(double) totalSchematas);
    return cast(long) f;
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

/**
DESCRIPTION

     The getloadavg() function returns the number of processes in the system
     run queue averaged over various periods of time.  Up to nelem samples are
     retrieved and assigned to successive elements of loadavg[].  The system
     imposes a maximum of 3 samples, representing averages over the last 1, 5,
     and 15 minutes, respectively.


DIAGNOSTICS

     If the load average was unobtainable, -1 is returned; otherwise, the num-
     ber of samples actually retrieved is returned.
 */
extern (C) int getloadavg(double* loadavg, int nelem) nothrow;
