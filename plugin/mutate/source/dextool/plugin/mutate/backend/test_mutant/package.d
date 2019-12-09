/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.test_mutant;

import core.thread : Thread;
import core.time : Duration, dur;
import logger = std.experimental.logger;
import std.algorithm : sort, map, splitter, filter;
import std.array : empty, array;
import std.datetime : SysTime, Clock;
import std.exception : collectException;
import std.path : buildPath;
import std.typecons : Nullable, NullableRef, nullableRef, Tuple;

import blob_model : Blob, Uri;
import sumtype;

import dextool.fsm : Fsm, next, act, get, TypeDataMap;
import dextool.plugin.mutate.backend.database : Database, MutationEntry,
    NextMutationEntry, spinSql, MutantTimeoutCtx, MutationId;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.test_mutant.interface_ : TestCaseReport;
import dextool.plugin.mutate.backend.type : Mutation, TestCase;
import dextool.plugin.mutate.config;
import dextool.plugin.mutate.type : TestCaseAnalyzeBuiltin;
import dextool.set;
import dextool.type : AbsolutePath, ShellCommand, ExitStatusType, FileName, DirName, Path;

@safe:

auto makeTestMutant() {
    return BuildTestMutant();
}

private:

struct BuildTestMutant {
@safe:
nothrow:

    import dextool.plugin.mutate.type : MutationKind;

    private struct InternalData {
        Mutation.Kind[] mut_kinds;
        FilesysIO filesys_io;
        ConfigMutationTest config;
    }

    private InternalData data;

    auto config(ConfigMutationTest c) {
        data.config = c;
        return this;
    }

    auto mutations(MutationKind[] v) {
        import dextool.plugin.mutate.backend.utility : toInternal;

        data.mut_kinds = toInternal(v);
        return this;
    }

    ExitStatusType run(ref Database db, FilesysIO fio) nothrow {
        auto mutationFactory(DriverData d, Duration test_base_timeout, MutationEntry mutp) @safe nothrow {
            import std.typecons : Unique;
            import dextool.plugin.mutate.backend.test_mutant.interface_ : GatherTestCase;

            try {
                auto global = MutationTestDriver.Global(d.filesysIO, d.db, d.autoCleanup, mutp);
                global.test_cases = new GatherTestCase;
                return Unique!MutationTestDriver(new MutationTestDriver(global,
                        MutationTestDriver.TestMutantData(!(d.conf.mutationTestCaseAnalyze.empty
                        && d.conf.mutationTestCaseBuiltin.empty), d.conf.mutationCompile,
                        d.conf.mutationTester, test_base_timeout),
                        MutationTestDriver.TestCaseAnalyzeData(d.conf.mutationTestCaseAnalyze,
                        d.conf.mutationTestCaseBuiltin,)));
            } catch (Exception e) {
                logger.error(e.msg).collectException;
            }
            assert(0, "should not happen");
        }

        // trusted because the lifetime of the database is guaranteed to outlive any instances in this scope
        auto db_ref = () @trusted { return nullableRef(&db); }();

        auto driver_data = DriverData(db_ref, fio, data.mut_kinds, new AutoCleanup, data.config);

        auto test_driver = TestDriver!mutationFactory(driver_data);

        while (test_driver.isRunning) {
            test_driver.execute;
        }

        return test_driver.status;
    }
}

immutable stdoutLog = "stdout.log";
immutable stderrLog = "stderr.log";

struct DriverData {
    NullableRef!Database db;
    FilesysIO filesysIO;
    Mutation.Kind[] mutKind;
    AutoCleanup autoCleanup;
    ConfigMutationTest conf;
}

/** Run the test suite to verify a mutation.
 *
 * Params:
 *  p = ?
 *  timeout = timeout threshold.
 */
Mutation.Status runTester(WatchdogT)(ShellCommand compile_p, ShellCommand tester_p,
        AbsolutePath test_output_dir, WatchdogT watchdog, FilesysIO fio) nothrow {
    import std.algorithm : among;
    import std.datetime.stopwatch : StopWatch;
    import dextool.plugin.mutate.backend.linux_process : spawnSession, tryWait, kill, wait;
    import std.stdio : File;
    import core.sys.posix.signal : SIGKILL;
    import dextool.plugin.mutate.backend.utility : rndSleep;

    Mutation.Status rval;

    try {
        auto p = spawnSession(compile_p.program ~ compile_p.arguments);
        auto res = p.wait;
        if (res.terminated && res.status != 0)
            return Mutation.Status.killedByCompiler;
        else if (!res.terminated) {
            logger.warning("unknown error when executing the compiler").collectException;
            return Mutation.Status.unknown;
        }
    } catch (Exception e) {
        logger.warning(e.msg).collectException;
    }

    string stdout_p;
    string stderr_p;

    if (test_output_dir.length != 0) {
        stdout_p = buildPath(test_output_dir, stdoutLog);
        stderr_p = buildPath(test_output_dir, stderrLog);
    }

    try {
        auto p = spawnSession(tester_p.program ~ tester_p.arguments, stdout_p, stderr_p);
        // trusted: killing the process started in this scope
        void cleanup() @safe nothrow {
            import core.sys.posix.signal : SIGKILL;

            if (rval.among(Mutation.Status.timeout, Mutation.Status.unknown)) {
                kill(p, SIGKILL);
                wait(p);
            }
        }

        scope (exit)
            cleanup;

        rval = Mutation.Status.timeout;
        watchdog.start;
        while (watchdog.isOk) {
            auto res = tryWait(p);
            if (res.terminated) {
                if (res.status == 0)
                    rval = Mutation.Status.alive;
                else
                    rval = Mutation.Status.killed;
                break;
            }

            rndSleep(10.dur!"msecs", 50);
        }
    } catch (Exception e) {
        // unable to for example execute the test suite
        logger.warning(e.msg).collectException;
        return Mutation.Status.unknown;
    }

    return rval;
}

struct MeasureTestDurationResult {
    ExitStatusType status;
    Duration runtime;
}

/**
 * If the tests fail (exit code isn't 0) any time then they are too unreliable
 * to use for mutation testing.
 *
 * The runtime is the lowest of the three executions.
 *
 * Params:
 *  p = ?
 */
MeasureTestDurationResult measureTesterDuration(ShellCommand cmd) nothrow {
    if (cmd.program.length == 0) {
        collectException(logger.error("No test suite runner specified (--mutant-tester)"));
        return MeasureTestDurationResult(ExitStatusType.Errors);
    }

    auto any_failure = ExitStatusType.Ok;

    void fun() {
        import std.process : execute;

        auto res = execute(cmd.program ~ cmd.arguments);
        if (res.status != 0)
            any_failure = ExitStatusType.Errors;
    }

    import std.datetime.stopwatch : benchmark;
    import std.algorithm : minElement;

    try {
        auto bench = benchmark!fun(3);

        if (any_failure != ExitStatusType.Ok)
            return MeasureTestDurationResult(ExitStatusType.Errors);

        auto a = (cast(long)((bench[0].total!"msecs") / 3.0)).dur!"msecs";
        return MeasureTestDurationResult(ExitStatusType.Ok, a);
    } catch (Exception e) {
        collectException(logger.error(e.msg));
        return MeasureTestDurationResult(ExitStatusType.Errors);
    }
}

/** Drive the control flow when testing **a** mutant.
 */
struct MutationTestDriver {
    import std.datetime.stopwatch : StopWatch;
    import dextool.plugin.mutate.backend.test_mutant.interface_ : GatherTestCase;

    static struct Global {
        FilesysIO fio;
        NullableRef!Database db;
        AutoCleanup auto_cleanup;
        MutationEntry mutp;

        AbsolutePath mut_file;
        Blob original;

        Mutation.Status mut_status;

        GatherTestCase test_cases;

        StopWatch sw;
    }

    static struct TestMutantData {
        /// If the user has configured that the test cases should be analyzed.
        bool hasTestCaseOutputAnalyzer;
        ShellCommand compile_cmd;
        ShellCommand test_cmd;
        Duration tester_runtime;
    }

    static struct TestCaseAnalyzeData {
        AbsolutePath test_case_cmd;
        const(TestCaseAnalyzeBuiltin)[] tc_analyze_builtin;
        /// Temporary directory where stdout/stderr should be written.
        AbsolutePath test_tmp_output;
    }

    static struct None {
    }

    static struct Initialize {
    }

    static struct MutateCode {
        bool next;
        bool filesysError;
        bool mutationError;
    }

    static struct TestMutant {
        bool next;
        bool mutationError;
    }

    static struct RestoreCode {
        bool next;
        bool filesysError;
    }

    static struct TestCaseAnalyze {
        bool next;
        bool mutationError;
        bool unstableTests;
    }

    static struct StoreResult {
    }

    static struct Done {
    }

    static struct FilesysError {
    }

    // happens when an error occurs during mutations testing but that do not
    // prohibit testing of other mutants
    static struct NoResultRestoreCode {
    }

    static struct NoResult {
    }

    alias Fsm = dextool.fsm.Fsm!(None, Initialize, MutateCode, TestMutant, RestoreCode,
            TestCaseAnalyze, StoreResult, Done, FilesysError, NoResultRestoreCode, NoResult);
    Fsm fsm;

    Global global;
    MutationTestResult result;

    alias LocalStateDataT = Tuple!(TestMutantData, TestCaseAnalyzeData);
    TypeDataMap!(LocalStateDataT, TestMutant, TestCaseAnalyze) local;

    this(Global global, TestMutantData l1, TestCaseAnalyzeData l2) {
        this.global = global;
        this.local = LocalStateDataT(l1, l2);
    }

    void execute_() {
        fsm.next!((None a) => fsm(Initialize.init),
                (Initialize a) => fsm(MutateCode.init), (MutateCode a) {
            if (a.next)
                return fsm(TestMutant.init);
            else if (a.filesysError)
                return fsm(FilesysError.init);
            else if (a.mutationError)
                return fsm(NoResultRestoreCode.init);
            return fsm(a);
        }, (TestMutant a) {
            if (a.next)
                return fsm(TestCaseAnalyze.init);
            else if (a.mutationError)
                return fsm(NoResultRestoreCode.init);
            return fsm(a);
        }, (TestCaseAnalyze a) {
            if (a.next)
                return fsm(RestoreCode.init);
            else if (a.mutationError || a.unstableTests)
                return fsm(NoResultRestoreCode.init);
            return fsm(a);
        }, (RestoreCode a) {
            if (a.next)
                return fsm(StoreResult.init);
            else if (a.filesysError)
                return fsm(FilesysError.init);
            return fsm(a);
        }, (StoreResult a) { return fsm(Done.init); }, (Done a) => fsm(a),
                (FilesysError a) => fsm(a),
                (NoResultRestoreCode a) => fsm(NoResult.init), (NoResult a) => fsm(a),);

        fsm.act!((None a) {}, (Initialize a) { global.sw.start; }, this, (Done a) {
        }, (FilesysError a) {
            logger.warning("Filesystem error").collectException;
        }, (NoResultRestoreCode a) { RestoreCode tmp; this.opCall(tmp); }, (NoResult a) {
        },);
    }

nothrow:

    void execute() {
        try {
            this.execute_();
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    /// Returns: true as long as the driver is processing a mutant.
    bool isRunning() {
        return !fsm.isState!(Done, NoResult, FilesysError);
    }

    bool stopBecauseError() {
        return fsm.isState!(FilesysError);
    }

    void opCall(ref MutateCode data) {
        import std.random : uniform;
        import dextool.plugin.mutate.backend.generate_mutant : generateMutant,
            GenerateMutantResult, GenerateMutantStatus;

        try {
            global.mut_file = AbsolutePath(FileName(global.mutp.file),
                    DirName(global.fio.getOutputDir));
            global.original = global.fio.makeInput(global.mut_file);
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            logger.warning("Unable to read ", global.mut_file).collectException;
            data.filesysError = true;
            return;
        }

        // mutate
        try {
            auto fout = global.fio.makeOutput(global.mut_file);
            auto mut_res = generateMutant(global.db.get, global.mutp, global.original, fout);

            final switch (mut_res.status) with (GenerateMutantStatus) {
            case error:
                data.mutationError = true;
                break;
            case filesysError:
                data.filesysError = true;
                break;
            case databaseError:
                // such as when the database is locked
                data.mutationError = true;
                break;
            case checksumError:
                data.filesysError = true;
                break;
            case noMutation:
                data.mutationError = true;
                break;
            case ok:
                data.next = true;
                try {
                    logger.infof("%s from '%s' to '%s' in %s:%s:%s", global.mutp.id,
                            cast(const(char)[]) mut_res.from, cast(const(char)[]) mut_res.to,
                            global.mut_file, global.mutp.sloc.line, global.mutp.sloc.column);

                } catch (Exception e) {
                    logger.warning("Mutation ID", e.msg);
                }
                break;
            }
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            data.mutationError = true;
        }
    }

    void opCall(ref TestMutant data) {
        if (local.get!TestMutant.hasTestCaseOutputAnalyzer) {
            try {
                auto tmpdir = createTmpDir(global.mutp.id);
                if (tmpdir.length == 0) {
                    data.mutationError = true;
                    return;
                }
                local.get!TestCaseAnalyze.test_tmp_output = Path(tmpdir).AbsolutePath;
                global.auto_cleanup.add(local.get!TestCaseAnalyze.test_tmp_output);
            } catch (Exception e) {
                logger.warning(e.msg).collectException;
                data.mutationError = true;
                return;
            }
        }

        try {
            import dextool.plugin.mutate.backend.watchdog : StaticTime;

            auto watchdog = StaticTime!StopWatch(local.get!TestMutant.tester_runtime);

            global.mut_status = runTester(local.get!TestMutant.compile_cmd, local.get!TestMutant.test_cmd,
                    local.get!TestCaseAnalyze.test_tmp_output, watchdog, global.fio);
            data.next = true;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            data.mutationError = true;
        }
    }

    void opCall(ref TestCaseAnalyze data) {
        import std.ascii : newline;
        import std.file : exists;
        import std.process : execute;
        import std.string : strip;

        if (global.mut_status != Mutation.Status.killed
                || local.get!TestCaseAnalyze.test_tmp_output.empty) {
            data.next = true;
            return;
        }

        try {
            auto stdout_ = buildPath(local.get!TestCaseAnalyze.test_tmp_output, stdoutLog);
            auto stderr_ = buildPath(local.get!TestCaseAnalyze.test_tmp_output, stderrLog);

            if (!exists(stdout_) || !exists(stderr_)) {
                logger.warningf("Unable to open %s and %s for test case analyze", stdout_, stderr_);
                data.mutationError = true;
                return;
            }

            auto gather_tc = new GatherTestCase;

            // the post processer must succeeed for the data to be stored. if
            // is considered a major error that may corrupt existing data if it
            // fails.
            bool success = true;

            if (!local.get!TestCaseAnalyze.test_case_cmd.empty) {
                success = success && externalProgram([
                        local.get!TestCaseAnalyze.test_case_cmd, stdout_, stderr_
                        ], gather_tc);
            }
            if (!local.get!TestCaseAnalyze.tc_analyze_builtin.empty) {
                success = success && builtin(global.fio.getOutputDir, [
                        stdout_, stderr_
                        ], local.get!TestCaseAnalyze.tc_analyze_builtin, gather_tc);
            }

            if (!gather_tc.unstable.empty) {
                logger.warningf("Unstable test cases found: [%-(%s, %)]",
                        gather_tc.unstableAsArray);
                logger.info(
                        "As configured the result is ignored which will force the mutant to be re-tested");
                data.unstableTests = true;
            } else if (success) {
                global.test_cases = gather_tc;
                // TODO: this is stupid... do not use bools
                data.next = true;
            }
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    void opCall(StoreResult data) {
        global.sw.stop;
        result.value = MutationTestResult.StatusUpdate(global.mutp.id,
                global.mut_status, global.sw.peek, global.test_cases.failedAsArray);
    }

    void opCall(ref RestoreCode data) {
        // restore the original file.
        try {
            global.fio.makeOutput(global.mut_file).write(global.original.content);
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            // fatal error because being unable to restore a file prohibit
            // future mutations.
            data.filesysError = true;
            return;
        }

        data.next = true;
    }
}

struct TestDriver(alias mutationDriverFactory) {
    import std.datetime : SysTime;
    import std.typecons : Unique;
    import dextool.plugin.mutate.backend.test_mutant.timeout : calculateTimeout, TimeoutFsm;

    static struct Global {
        DriverData data;
        Unique!MutationTestDriver mut_driver;

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
    }

    static struct SanityCheck {
        bool sanityCheckFailed;
    }

    static struct UpdateAndResetAliveMutants {
    }

    static struct ResetOldMutant {
        bool doneTestingOldMutants;
    }

    static struct ResetOldMutantData {
        /// Number of mutants that where reset.
        long resetCount;
        long maxReset;
    }

    static struct CleanupTempDirs {
    }

    static struct CheckMutantsLeft {
        bool allMutantsTested;
    }

    static struct ParseStdin {
    }

    static struct PreCompileSut {
        bool compilationError;
    }

    static struct MeasureTestSuite {
        bool unreliableTestSuite;
    }

    static struct PreMutationTest {
    }

    static struct MutationTest {
        bool next;
        bool mutationError;
        MutationTestResult result;
    }

    static struct CheckTimeout {
        bool timeoutUnchanged;
    }

    static struct Done {
    }

    static struct Error {
    }

    static struct UpdateTimeout {
    }

    static struct NextPullRequestMutant {
        bool noUnknownMutantsLeft;
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
        bool noUnknownMutantsLeft;
    }

    static struct HandleTestResult {
        MutationTestResult result;
    }

    static struct CheckRuntime {
        bool reachedMax;
    }

    static struct SetMaxRuntime {
    }

    alias Fsm = dextool.fsm.Fsm!(None, Initialize, SanityCheck,
            UpdateAndResetAliveMutants, ResetOldMutant, CleanupTempDirs,
            CheckMutantsLeft, PreCompileSut, MeasureTestSuite, PreMutationTest,
            NextMutant, MutationTest, HandleTestResult, CheckTimeout,
            Done, Error, UpdateTimeout, CheckRuntime, SetMaxRuntime,
            PullRequest, NextPullRequestMutant, ParseStdin);

    Fsm fsm;

    Global global;

    alias LocalStateDataT = Tuple!(UpdateTimeoutData,
            NextPullRequestMutantData, PullRequestData, ResetOldMutantData);
    TypeDataMap!(LocalStateDataT, UpdateTimeout, NextPullRequestMutant,
            PullRequest, ResetOldMutant) local;

    this(DriverData data) {
        this.global = Global(data);
        this.global.timeoutFsm = TimeoutFsm(data.mutKind);
        this.global.hardcodedTimeout = !global.data.conf.mutationTesterRuntime.isNull;
        local.get!PullRequest.constraint = global.data.conf.constraint;
        local.get!NextPullRequestMutant.maxAlive = global.data.conf.maxAlive;
        local.get!ResetOldMutant.maxReset = global.data.conf.oldMutantsNr;
    }

    void execute_() {
        // see test_mutant/basis.md and figures/test_mutant_fsm.pu for a
        // graphical view of the state machine.

        fsm.next!((None a) => fsm(Initialize.init),
                (Initialize a) => fsm(SanityCheck.init), (SanityCheck a) {
            if (a.sanityCheckFailed)
                return fsm(Error.init);
            if (global.data.conf.unifiedDiffFromStdin)
                return fsm(ParseStdin.init);
            return fsm(PreCompileSut.init);
        }, (ParseStdin a) => fsm(PreCompileSut.init),
                (UpdateAndResetAliveMutants a) => fsm(CheckMutantsLeft.init), (ResetOldMutant a) {
            if (a.doneTestingOldMutants)
                return fsm(Done.init);
            return fsm(UpdateTimeout.init);
        }, (CleanupTempDirs a) {
            if (local.get!PullRequest.constraint.empty)
                return fsm(NextMutant.init);
            return fsm(NextPullRequestMutant.init);
        }, (CheckMutantsLeft a) {
            if (a.allMutantsTested
                && global.data.conf.onOldMutants == ConfigMutationTest.OldMutant.nothing)
                return fsm(Done.init);
            return fsm(MeasureTestSuite.init);
        }, (PreCompileSut a) {
            if (a.compilationError)
                return fsm(Error.init);
            if (local.get!PullRequest.constraint.empty)
                return fsm(UpdateAndResetAliveMutants.init);
            return fsm(PullRequest.init);
        }, (PullRequest a) => fsm(CheckMutantsLeft.init), (MeasureTestSuite a) {
            if (a.unreliableTestSuite)
                return fsm(Error.init);
            return fsm(SetMaxRuntime.init);
        }, (SetMaxRuntime a) => fsm(UpdateTimeout.init), (NextPullRequestMutant a) {
            if (a.noUnknownMutantsLeft)
                return fsm(Done.init);
            return fsm(PreMutationTest.init);
        }, (NextMutant a) {
            if (a.noUnknownMutantsLeft)
                return fsm(CheckTimeout.init);
            return fsm(PreMutationTest.init);
        }, (PreMutationTest a) => fsm(MutationTest.init),
                (UpdateTimeout a) => fsm(CleanupTempDirs.init), (MutationTest a) {
            if (a.next)
                return fsm(HandleTestResult(a.result));
            else if (a.mutationError)
                return fsm(Error.init);
            return fsm(a);
        }, (HandleTestResult a) => fsm(CheckRuntime.init), (CheckRuntime a) {
            if (a.reachedMax)
                return fsm(Done.init);
            return fsm(UpdateTimeout.init);
        }, (CheckTimeout a) {
            if (a.timeoutUnchanged)
                return fsm(ResetOldMutant.init);
            return fsm(UpdateTimeout.init);
        }, (Done a) => fsm(a), (Error a) => fsm(a),);

        fsm.act!((None a) {}, (Initialize a) {}, this,);
    }

nothrow:
    void execute() {
        try {
            this.execute_();
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    bool isRunning() {
        return !fsm.isState!(Done, Error);
    }

    ExitStatusType status() {
        if (fsm.isState!Done)
            return ExitStatusType.Ok;
        return ExitStatusType.Errors;
    }

    void opCall(Done data) {
        global.data.autoCleanup.cleanup;

        logger.info("Done!").collectException;
    }

    void opCall(Error data) {
        global.data.autoCleanup.cleanup;
    }

    void opCall(ref SanityCheck data) {
        // #SPC-sanity_check_db_vs_filesys
        import dextool.plugin.mutate.backend.utility : checksum, trustedRelativePath;
        import dextool.plugin.mutate.backend.type : Checksum;

        const(Path)[] files;
        spinSql!(() { files = global.data.db.getFiles; });

        bool has_sanity_check_failed;
        for (size_t i; i < files.length;) {
            Checksum db_checksum;
            spinSql!(() { db_checksum = global.data.db.getFileChecksum(files[i]); });

            try {
                auto abs_f = AbsolutePath(FileName(files[i]),
                        DirName(cast(string) global.data.filesysIO.getOutputDir));
                auto f_checksum = checksum(global.data.filesysIO.makeInput(abs_f).content[]);
                if (db_checksum != f_checksum) {
                    logger.errorf("Mismatch between the file on the filesystem and the analyze of '%s'",
                            abs_f);
                    has_sanity_check_failed = true;
                }
            } catch (Exception e) {
                // assume it is a problem reading the file or something like that.
                has_sanity_check_failed = true;
                logger.trace(e.msg).collectException;
            }

            // all done. continue with the next file
            ++i;
        }

        if (has_sanity_check_failed) {
            data.sanityCheckFailed = true;
            logger.error("Detected that one or more file has changed since last analyze where done")
                .collectException;
            logger.error("Either restore the files to the previous state or rerun the analyzer")
                .collectException;
        } else {
            logger.info("Sanity check passed. Files on the filesystem are consistent")
                .collectException;
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

    // TODO: refactor. This method is too long.
    void opCall(UpdateAndResetAliveMutants data) {
        import std.datetime.stopwatch : StopWatch;
        import dextool.plugin.mutate.backend.type : TestCase;

        if (global.data.conf.mutationTestCaseAnalyze.length == 0
                && global.data.conf.mutationTestCaseBuiltin.length == 0)
            return;

        AbsolutePath test_tmp_output;
        try {
            auto tmpdir = createTmpDir(0);
            if (tmpdir.length == 0)
                return;
            test_tmp_output = Path(tmpdir).AbsolutePath;
            global.data.autoCleanup.add(test_tmp_output);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            return;
        }

        TestCase[] all_found_tc;

        try {
            import dextool.plugin.mutate.backend.test_mutant.interface_ : GatherTestCase;
            import dextool.plugin.mutate.backend.watchdog : StaticTime;

            auto stdout_ = buildPath(test_tmp_output, stdoutLog);
            auto stderr_ = buildPath(test_tmp_output, stderrLog);

            // using an unreasonable timeout because this is more intended to reuse the functionality in runTester
            auto watchdog = StaticTime!StopWatch(999.dur!"hours");
            runTester(global.data.conf.mutationCompile, global.data.conf.mutationTester,
                    test_tmp_output, watchdog, global.data.filesysIO);

            auto gather_tc = new GatherTestCase;

            if (global.data.conf.mutationTestCaseAnalyze.length != 0) {
                externalProgram([
                        global.data.conf.mutationTestCaseAnalyze, stdout_, stderr_
                        ], gather_tc);
                logger.warningf(gather_tc.unstable.length != 0,
                        "Unstable test cases found: [%-(%s, %)]", gather_tc.unstableAsArray);
            }
            if (global.data.conf.mutationTestCaseBuiltin.length != 0) {
                builtin(global.data.filesysIO.getOutputDir, [stdout_, stderr_],
                        global.data.conf.mutationTestCaseBuiltin, gather_tc);
            }

            all_found_tc = gather_tc.foundAsArray;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }

        warnIfConflictingTestCaseIdentifiers(all_found_tc);

        // the test cases before anything has potentially changed.
        Set!string old_tcs;
        spinSql!(() {
            foreach (tc; global.data.db.getDetectedTestCases)
                old_tcs.add(tc.name);
        });

        final switch (global.data.conf.onRemovedTestCases) with (
            ConfigMutationTest.RemovedTestCases) {
        case doNothing:
            spinSql!(() { global.data.db.addDetectedTestCases(all_found_tc); });
            break;
        case remove:
            auto ids = spinSql!(() {
                return global.data.db.setDetectedTestCases(all_found_tc);
            });
            foreach (id; ids)
                spinSql!(() {
                    global.data.db.updateMutationStatus(id, Mutation.Status.unknown);
                });
            break;
        }

        Set!string found_tcs;
        spinSql!(() {
            foreach (tc; global.data.db.getDetectedTestCases)
                found_tcs.add(tc.name);
        });

        printDroppedTestCases(old_tcs, found_tcs);

        const new_test_cases = hasNewTestCases(old_tcs, found_tcs);

        if (new_test_cases
                && global.data.conf.onNewTestCases == ConfigMutationTest.NewTestCases.resetAlive) {
            logger.info("Resetting alive mutants").collectException;
            resetAliveMutants(global.data.db);
        }
    }

    void opCall(ref ResetOldMutant data) {
        import dextool.plugin.mutate.backend.database.type;

        if (global.data.conf.onOldMutants == ConfigMutationTest.OldMutant.nothing) {
            data.doneTestingOldMutants = true;
            return;
        }
        if (Clock.currTime > global.maxRuntime) {
            data.doneTestingOldMutants = true;
            return;
        }
        if (local.get!ResetOldMutant.resetCount >= local.get!ResetOldMutant.maxReset) {
            data.doneTestingOldMutants = true;
            return;
        }

        local.get!ResetOldMutant.resetCount++;

        logger.infof("Resetting an old mutant (%s/%s)", local.get!ResetOldMutant.resetCount,
                local.get!ResetOldMutant.maxReset).collectException;
        auto oldest = spinSql!(() {
            return global.data.db.getOldestMutants(global.data.mutKind, 1);
        });

        foreach (const old; oldest) {
            logger.info("Last updated ", old.updated).collectException;
            spinSql!(() {
                global.data.db.updateMutationStatus(old.id, Mutation.Status.unknown);
            });
        }
    }

    void opCall(CleanupTempDirs data) {
        global.data.autoCleanup.cleanup;
    }

    void opCall(ref CheckMutantsLeft data) {
        spinSql!(() { global.timeoutFsm.execute(global.data.db); });

        data.allMutantsTested = global.timeoutFsm.output.done;

        if (global.timeoutFsm.output.done) {
            logger.info("All mutants are tested").collectException;
        }
    }

    void opCall(ref PreCompileSut data) {
        logger.info("Preparing for mutation testing by checking that the program and tests compile without any errors (no mutants injected)")
            .collectException;

        try {
            import std.process : execute;

            const comp_res = execute(
                    global.data.conf.mutationCompile.program
                    ~ global.data.conf.mutationCompile.arguments);

            if (comp_res.status != 0) {
                data.compilationError = true;
                logger.info(comp_res.output);
                logger.error("Compiler command failed: ", comp_res.status);
            }
        } catch (Exception e) {
            // unable to for example execute the compiler
            logger.error(e.msg).collectException;
        }
    }

    void opCall(PullRequest data) {
        import std.array : appender;
        import dextool.plugin.mutate.backend.database : MutationStatusId;
        import dextool.plugin.mutate.backend.type : SourceLoc;
        import dextool.set;

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
                    return global.data.db.getMutationsOnLine(global.data.mutKind,
                        file_id.get, SourceLoc(l.value, 0));
                });

                const pre_cnt = mut_ids.length;
                foreach (v; mutants)
                    mut_ids.add(v);

                logger.infof(mut_ids.length - pre_cnt > 0, "Found %s mutant(s) to test (%s:%s)",
                        mut_ids.length - pre_cnt, kv.key, l.value).collectException;
            }
        }

        local.get!NextPullRequestMutant.mutants = mut_ids.toArray;
        logger.trace(local.get!NextPullRequestMutant.mutants.sort).collectException;

        if (mut_ids.empty) {
            logger.warning("None of the locations specified with -L exists").collectException;
            logger.info("Available files are:").collectException;
            foreach (f; spinSql!(() => global.data.db.getFiles))
                logger.info(f).collectException;
        }
    }

    void opCall(ref MeasureTestSuite data) {
        if (global.data.conf.mutationTesterRuntime.isNull) {
            logger.info("Measuring the time to run the tests: ",
                    global.data.conf.mutationTester).collectException;
            auto tester = measureTesterDuration(global.data.conf.mutationTester);
            if (tester.status == ExitStatusType.Ok) {
                // The sampling of the test suite become too unreliable when the timeout is <1s.
                // This is a quick and dirty fix.
                // A proper fix requires an update of the sampler in runTester.
                auto t = tester.runtime < 1.dur!"seconds" ? 1.dur!"seconds" : tester.runtime;
                logger.info("Tester measured to: ", t).collectException;
                global.testSuiteRuntime = t;
            } else {
                data.unreliableTestSuite = true;
                logger.error(
                        "Test suite is unreliable. It must return exit status '0' when running with unmodified mutants")
                    .collectException;
            }
        } else {
            global.testSuiteRuntime = global.data.conf.mutationTesterRuntime.get;
        }
    }

    void opCall(PreMutationTest) {
        global.mut_driver = mutationDriverFactory(global.data,
                calculateTimeout(global.timeoutFsm.output.iter, global.testSuiteRuntime),
                global.nextMutant);
    }

    void opCall(ref MutationTest data) {
        if (global.mut_driver.isRunning) {
            global.mut_driver.execute();
        } else if (global.mut_driver.stopBecauseError) {
            data.mutationError = true;
        } else {
            data.result = global.mut_driver.result;
            data.next = true;
        }
    }

    void opCall(ref CheckTimeout data) {
        data.timeoutUnchanged = global.hardcodedTimeout || global.timeoutFsm.output.done;
    }

    void opCall(UpdateTimeout) {
        spinSql!(() { global.timeoutFsm.execute(global.data.db); });

        const lastIter = local.get!UpdateTimeout.lastTimeoutIter;

        if (lastIter != global.timeoutFsm.output.iter) {
            logger.infof("Changed the timeout from %s to %s (iteration %s)",
                    calculateTimeout(lastIter, global.testSuiteRuntime),
                    calculateTimeout(global.timeoutFsm.output.iter, global.testSuiteRuntime),
                    global.timeoutFsm.output.iter).collectException;
            local.get!UpdateTimeout.lastTimeoutIter = global.timeoutFsm.output.iter;
        }
    }

    void opCall(ref NextPullRequestMutant data) {
        global.nextMutant = MutationEntry.init;
        data.noUnknownMutantsLeft = true;

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

            const info = spinSql!(() => global.data.db.getMutantsInfo(global.data.mutKind, [
                        id
                    ]));
            if (info.empty)
                continue;

            global.nextMutant = spinSql!(() => global.data.db.getMutation(info[0].id));
            data.noUnknownMutantsLeft = false;
            break;
        }

        if (!local.get!NextPullRequestMutant.maxAlive.isNull) {
            const alive = local.get!NextPullRequestMutant.alive;
            const maxAlive = local.get!NextPullRequestMutant.maxAlive.get;
            logger.infof(alive > 0, "Found %s/%s alive mutants", alive, maxAlive).collectException;
            if (alive >= maxAlive) {
                data.noUnknownMutantsLeft = true;
            }
        }
    }

    void opCall(ref NextMutant data) {
        global.nextMutant = MutationEntry.init;

        auto next = spinSql!(() {
            return global.data.db.nextMutation(global.data.mutKind);
        });

        data.noUnknownMutantsLeft = next.st == NextMutationEntry.Status.done;

        if (!next.entry.isNull) {
            global.nextMutant = next.entry.get;
        }
    }

    void opCall(HandleTestResult data) {
        void statusUpdate(MutationTestResult.StatusUpdate result) {
            import dextool.plugin.mutate.backend.test_mutant.timeout : updateMutantStatus;

            const cnt_action = () {
                if (result.status == Mutation.Status.alive)
                    return Database.CntAction.incr;
                return Database.CntAction.reset;
            }();

            auto statusId = spinSql!(() {
                return global.data.db.getMutationStatusId(result.id);
            });
            if (statusId.isNull)
                return;

            spinSql!(() @trusted {
                auto t = global.data.db.transaction;
                updateMutantStatus(global.data.db, statusId.get, result.status,
                    global.timeoutFsm.output.iter);
                global.data.db.updateMutation(statusId.get, cnt_action);
                global.data.db.updateMutation(statusId.get, result.testTime);
                global.data.db.updateMutationTestCases(statusId.get, result.testCases);
                t.commit;
            });

            logger.infof("%s %s (%s)", result.id, result.status, result.testTime).collectException;
            logger.infof(result.testCases.length != 0, `%s killed by [%-(%s, %)]`,
                    result.id, result.testCases.sort.map!"a.name").collectException;
        }

        data.result.value.match!((MutationTestResult.NoResult a) {},
                (MutationTestResult.StatusUpdate a) => statusUpdate(a));
    }

    void opCall(SetMaxRuntime) {
        global.maxRuntime = Clock.currTime + global.data.conf.maxRuntime;
    }

    void opCall(ref CheckRuntime data) {
        data.reachedMax = Clock.currTime > global.maxRuntime;
        if (data.reachedMax) {
            logger.infof("Max runtime of %s reached at %s",
                    global.data.conf.maxRuntime, global.maxRuntime).collectException;
        }
    }
}

private:

/// Run an external program that analyze the output from the test suite for test cases that failed.
bool externalProgram(string[] cmd, TestCaseReport report) nothrow {
    import std.algorithm : copy;
    import std.ascii : newline;
    import std.process : execute;
    import std.string : strip, startsWith;

    immutable passed = "passed:";
    immutable failed = "failed:";
    immutable unstable = "unstable:";

    try {
        // [test_case_cmd, stdout_, stderr_]
        auto p = execute(cmd);
        if (p.status == 0) {
            foreach (l; p.output.splitter(newline).map!(a => a.strip)
                    .filter!(a => a.length != 0)) {
                if (l.startsWith(passed))
                    report.reportFound(TestCase(l[passed.length .. $].strip));
                else if (l.startsWith(failed))
                    report.reportFailed(TestCase(l[failed.length .. $].strip));
                else if (l.startsWith(unstable))
                    report.reportUnstable(TestCase(l[unstable.length .. $].strip));
            }
            return true;
        } else {
            logger.warning(p.output);
            logger.warning("Failed to analyze the test case output");
            return false;
        }
    } catch (Exception e) {
        logger.warning(e.msg).collectException;
    }

    return false;
}

/** Analyze the output from the test suite with one of the builtin analyzers.
 *
 * trusted: because the paths to the File object are created by this program
 * and can thus not lead to memory related problems.
 */
bool builtin(AbsolutePath reldir, string[] analyze_files,
        const(TestCaseAnalyzeBuiltin)[] tc_analyze_builtin, TestCaseReport app) @trusted nothrow {
    import std.stdio : File;
    import dextool.plugin.mutate.backend.test_mutant.ctest_post_analyze;
    import dextool.plugin.mutate.backend.test_mutant.gtest_post_analyze;
    import dextool.plugin.mutate.backend.test_mutant.makefile_post_analyze;

    foreach (f; analyze_files) {
        auto gtest = GtestParser(reldir);
        CtestParser ctest;
        MakefileParser makefile;

        File* fin;
        try {
            fin = new File(f);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            return false;
        }

        scope (exit)
            () {
            try {
                fin.close;
                destroy(fin);
            } catch (Exception e) {
                logger.warning(e.msg).collectException;
            }
        }();

        // an invalid UTF-8 char shall only result in the rest of the file being skipped
        try {
            foreach (l; fin.byLine) {
                // this is a magic number that felt good. Why would there be a line in a test case log that is longer than this?
                immutable magic_nr = 2048;
                if (l.length > magic_nr) {
                    // The byLine split may fail and thus result in one huge line.
                    // The result of this is that regex's that use backtracking become really slow.
                    // By skipping these lines dextool at list doesn't hang.
                    logger.warningf("Line in test case log is too long to analyze (%s > %s). Skipping...",
                            l.length, magic_nr);
                    continue;
                }

                foreach (const p; tc_analyze_builtin) {
                    final switch (p) {
                    case TestCaseAnalyzeBuiltin.gtest:
                        gtest.process(l, app);
                        break;
                    case TestCaseAnalyzeBuiltin.ctest:
                        ctest.process(l, app);
                        break;
                    case TestCaseAnalyzeBuiltin.makefile:
                        makefile.process(l, app);
                        break;
                    }
                }
            }
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    return true;
}

/// Returns: path to a tmp directory or null on failure.
string createTmpDir(long id) nothrow {
    import std.random : uniform;
    import std.format : format;
    import std.file : mkdir, exists;

    string test_tmp_output;

    // try 5 times or bailout
    foreach (const _; 0 .. 5) {
        try {
            auto tmp = format("dextool_tmp_id_%s_%s", id, uniform!ulong);
            mkdir(tmp);
            test_tmp_output = AbsolutePath(FileName(tmp));
            break;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    if (test_tmp_output.length == 0) {
        logger.warning("Unable to create a temporary directory to store stdout/stderr in")
            .collectException;
    }

    return test_tmp_output;
}

/// Reset all alive mutants.
void resetAliveMutants(ref Database db) @safe nothrow {
    import std.traits : EnumMembers;

    // there is no use in trying to limit the mutants to reset to those that
    // are part of "this" execution because new test cases can only mean one
    // thing: re-test all alive mutants.

    spinSql!(() {
        db.resetMutant([EnumMembers!(Mutation.Kind)], Mutation.Status.alive,
            Mutation.Status.unknown);
    });
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

/** Paths stored will be removed automatically either when manually called or goes out of scope.
 */
class AutoCleanup {
    private string[] remove_dirs;

    void add(AbsolutePath p) @safe nothrow {
        remove_dirs ~= cast(string) p;
    }

    // trusted: the paths are forced to be valid paths.
    void cleanup() @trusted nothrow {
        import std.file : rmdirRecurse, exists;

        foreach (ref p; remove_dirs.filter!(a => !a.empty)) {
            try {
                if (exists(p))
                    rmdirRecurse(p);
                if (!exists(p))
                    p = null;
            } catch (Exception e) {
                logger.info(e.msg).collectException;
            }
        }

        remove_dirs = remove_dirs.filter!(a => !a.empty).array;
    }
}

/// The result of testing a mutant.
struct MutationTestResult {
    static struct NoResult {
    }

    static struct StatusUpdate {
        MutationId id;
        Mutation.Status status;
        Duration testTime;
        TestCase[] testCases;
    }

    alias Value = SumType!(NoResult, StatusUpdate);
    Value value;
}
