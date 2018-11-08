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
import std.datetime : SysTime;
import std.typecons : Nullable, NullableRef, nullableRef;
import std.exception : collectException;

import logger = std.experimental.logger;

import dextool.plugin.mutate.backend.database : Database, MutationEntry,
    NextMutationEntry, spinSqlQuery;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config;
import dextool.plugin.mutate.type : TestCaseAnalyzeBuiltin;
import dextool.type : AbsolutePath, ExitStatusType, FileName, DirName;

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
        auto mutationFactory(DriverData data, Duration test_base_timeout) @safe {
            import std.typecons : Unique;

            static struct Rval {
                ImplMutationDriver impl;
                MutationTestDriver!(ImplMutationDriver*) driver;

                this(DriverData d, Duration test_base_timeout) {
                    this.impl = ImplMutationDriver(d.filesysIO, d.db, d.autoCleanup,
                            d.mutKind, d.conf.mutationCompile, d.conf.mutationTester, d.conf.mutationTestCaseAnalyze,
                            d.conf.mutationTestCaseBuiltin, test_base_timeout);

                    this.driver = MutationTestDriver!(ImplMutationDriver*)(() @trusted {
                        return &impl;
                    }());
                }

                alias driver this;
            }

            return Unique!Rval(new Rval(data, test_base_timeout));
        }

        // trusted because the lifetime of the database is guaranteed to outlive any instances in this scope
        auto db_ref = () @trusted { return nullableRef(&db); }();

        auto driver_data = DriverData(db_ref, fio, data.mut_kinds, new AutoCleanup, data.config);

        auto test_driver_impl = ImplTestDriver!mutationFactory(driver_data);
        auto test_driver_impl_ref = () @trusted {
            return nullableRef(&test_driver_impl);
        }();
        auto test_driver = TestDriver!(typeof(test_driver_impl_ref))(test_driver_impl_ref);

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
Mutation.Status runTester(WatchdogT)(AbsolutePath compile_p, AbsolutePath tester_p,
        AbsolutePath test_output_dir, WatchdogT watchdog, FilesysIO fio) nothrow {
    import std.algorithm : among;
    import std.datetime.stopwatch : StopWatch;
    import dextool.plugin.mutate.backend.linux_process : spawnSession, tryWait, kill, wait;
    import std.stdio : File;
    import core.sys.posix.signal : SIGKILL;
    import dextool.plugin.mutate.backend.utility : rndSleep;

    Mutation.Status rval;

    try {
        auto p = spawnSession([cast(string) compile_p]);
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
        import std.path : buildPath;

        stdout_p = buildPath(test_output_dir, stdoutLog);
        stderr_p = buildPath(test_output_dir, stderrLog);
    }

    try {
        auto p = spawnSession([cast(string) tester_p], stdout_p, stderr_p);
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
MeasureTestDurationResult measureTesterDuration(AbsolutePath p) nothrow {
    if (p.length == 0) {
        collectException(logger.error("No test suite runner specified (--mutant-tester)"));
        return MeasureTestDurationResult(ExitStatusType.Errors);
    }

    auto any_failure = ExitStatusType.Ok;

    void fun() {
        import std.process : execute;

        auto res = execute([cast(string) p]);
        if (res.status != 0)
            any_failure = ExitStatusType.Errors;
    }

    import std.datetime.stopwatch : benchmark;
    import std.algorithm : minElement, map;
    import core.time : dur;

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

enum MutationDriverSignal {
    /// stay in the current state
    stop,
    /// advance to the next state
    next,
    /// All mutants are tested. Stopping mutation testing
    allMutantsTested,
    /// An error occured when interacting with the filesystem (fatal). Stopping all mutation testing
    filesysError,
    /// An error for a single mutation. It is skipped.
    mutationError,
}

/** Drive the control flow when testing **a** mutant.
 *
 * The architecture assume that there will be behavior changes therefore a
 * strict FSM that separate the context, action and next_state.
 *
 * The intention is to separate the control flow from the implementation of the
 * actions that are done when mutation testing.
 */
struct MutationTestDriver(ImplT) {
    import std.experimental.typecons : Final;

    /// The internal state of the FSM.
    private enum State {
        none,
        initialize,
        mutateCode,
        testMutant,
        restoreCode,
        testCaseAnalyze,
        storeResult,
        done,
        allMutantsTested,
        filesysError,
        /// happens when an error occurs during mutations testing but that do not prohibit testing of other mutants
        noResultRestoreCode,
        noResult,
    }

    private {
        State st;
        ImplT impl;
    }

    this(ImplT impl) {
        this.impl = impl;
    }

    /// Returns: true as long as the driver is processing a mutant.
    bool isRunning() {
        import std.algorithm : among;

        return st.among(State.done, State.noResult, State.filesysError, State.allMutantsTested) == 0;
    }

    bool stopBecauseError() {
        return st == State.filesysError;
    }

    /// Returns: true when the mutation testing should be stopped
    bool stopMutationTesting() {
        return st == State.allMutantsTested;
    }

    void execute() {
        import dextool.fsm : generateActions;

        const auto signal = impl.signal;

        debug auto old_st = st;

        st = nextState(st, signal);

        debug logger.trace(old_st, "->", st, ":", signal).collectException;

        mixin(generateActions!(State, "st", "impl"));
    }

    private static State nextState(immutable State current, immutable MutationDriverSignal signal) @safe pure nothrow @nogc {
        State next_ = current;

        final switch (current) {
        case State.none:
            next_ = State.initialize;
            break;
        case State.initialize:
            if (signal == MutationDriverSignal.next)
                next_ = State.mutateCode;
            break;
        case State.mutateCode:
            if (signal == MutationDriverSignal.next)
                next_ = State.testMutant;
            else if (signal == MutationDriverSignal.allMutantsTested)
                next_ = State.allMutantsTested;
            else if (signal == MutationDriverSignal.filesysError)
                next_ = State.filesysError;
            else if (signal == MutationDriverSignal.mutationError)
                next_ = State.noResultRestoreCode;
            break;
        case State.testMutant:
            if (signal == MutationDriverSignal.next)
                next_ = State.testCaseAnalyze;
            else if (signal == MutationDriverSignal.mutationError)
                next_ = State.noResultRestoreCode;
            else if (signal == MutationDriverSignal.allMutantsTested)
                next_ = State.allMutantsTested;
            break;
        case State.testCaseAnalyze:
            if (signal == MutationDriverSignal.next)
                next_ = State.restoreCode;
            else if (signal == MutationDriverSignal.mutationError)
                next_ = State.noResultRestoreCode;
            break;
        case State.restoreCode:
            if (signal == MutationDriverSignal.next)
                next_ = State.storeResult;
            else if (signal == MutationDriverSignal.filesysError)
                next_ = State.filesysError;
            break;
        case State.storeResult:
            if (signal == MutationDriverSignal.next)
                next_ = State.done;
            break;
        case State.done:
            break;
        case State.allMutantsTested:
            break;
        case State.filesysError:
            break;
        case State.noResultRestoreCode:
            next_ = State.noResult;
            break;
        case State.noResult:
            break;
        }

        return next_;
    }
}

/** Implementation of the actions during the test of a mutant.
 *
 * The intention is that this driver do NOT control the flow.
 */
struct ImplMutationDriver {
    import std.datetime.stopwatch : StopWatch;
    import dextool.plugin.mutate.backend.test_mutant.interface_ : GatherTestCase;

nothrow:

    FilesysIO fio;
    NullableRef!Database db;

    StopWatch sw;
    MutationDriverSignal driver_sig;

    Nullable!MutationEntry mutp;
    AbsolutePath mut_file;
    const(ubyte)[] original_content;

    const(Mutation.Kind)[] mut_kind;
    const TestCaseAnalyzeBuiltin[] tc_analyze_builtin;

    AbsolutePath compile_cmd;
    AbsolutePath test_cmd;
    AbsolutePath test_case_cmd;
    Duration tester_runtime;

    /// Temporary directory where stdout/stderr should be written.
    AbsolutePath test_tmp_output;

    Mutation.Status mut_status;

    GatherTestCase test_cases;

    AutoCleanup auto_cleanup;

    this(FilesysIO fio, NullableRef!Database db, AutoCleanup auto_cleanup,
            Mutation.Kind[] mut_kind, AbsolutePath compile_cmd,
            AbsolutePath test_cmd, AbsolutePath test_case_cmd,
            TestCaseAnalyzeBuiltin[] tc_analyze_builtin, Duration tester_runtime) {
        this.fio = fio;
        this.db = db;
        this.mut_kind = mut_kind;
        this.compile_cmd = compile_cmd;
        this.test_cmd = test_cmd;
        this.test_case_cmd = test_case_cmd;
        this.tc_analyze_builtin = tc_analyze_builtin;
        this.tester_runtime = tester_runtime;
        this.test_cases = new GatherTestCase;
        this.auto_cleanup = auto_cleanup;
    }

    void none() {
    }

    void done() {
    }

    void allMutantsTested() {
    }

    void filesysError() {
        logger.warning("Filesystem error").collectException;
    }

    void noResultRestoreCode() {
        restoreCode;
    }

    void noResult() {
    }

    void initialize() {
        sw.start;
        driver_sig = MutationDriverSignal.next;
    }

    void mutateCode() {
        import core.thread : Thread;
        import std.random : uniform;
        import dextool.plugin.mutate.backend.generate_mutant : generateMutant,
            GenerateMutantResult, GenerateMutantStatus;

        driver_sig = MutationDriverSignal.stop;

        auto next_m = spinSqlQuery!(() { return db.nextMutation(mut_kind); });
        if (next_m.st == NextMutationEntry.Status.done) {
            logger.info("Done! All mutants are tested").collectException;
            driver_sig = MutationDriverSignal.allMutantsTested;
            return;
        } else {
            mutp = next_m.entry;
        }

        try {
            mut_file = AbsolutePath(FileName(mutp.file), DirName(fio.getOutputDir));

            // must duplicate because the buffer is memory mapped thus it can change
            original_content = fio.makeInput(mut_file).read.dup;
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            driver_sig = MutationDriverSignal.filesysError;
            return;
        }

        if (original_content.length == 0) {
            logger.warning("Unable to read ", mut_file).collectException;
            driver_sig = MutationDriverSignal.filesysError;
            return;
        }

        // mutate
        try {
            auto fout = fio.makeOutput(mut_file);
            auto mut_res = generateMutant(db.get, mutp, original_content, fout);

            final switch (mut_res.status) with (GenerateMutantStatus) {
            case error:
                driver_sig = MutationDriverSignal.mutationError;
                break;
            case filesysError:
                driver_sig = MutationDriverSignal.filesysError;
                break;
            case databaseError:
                // such as when the database is locked
                driver_sig = MutationDriverSignal.mutationError;
                break;
            case checksumError:
                driver_sig = MutationDriverSignal.filesysError;
                break;
            case noMutation:
                driver_sig = MutationDriverSignal.mutationError;
                break;
            case ok:
                driver_sig = MutationDriverSignal.next;
                try {
                    logger.infof("%s from '%s' to '%s' in %s:%s:%s", mutp.id,
                            cast(const(char)[]) mut_res.from, cast(const(char)[]) mut_res.to,
                            mut_file, mutp.sloc.line, mutp.sloc.column);

                } catch (Exception e) {
                    logger.warning("Mutation ID", e.msg);
                }
                break;
            }
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            driver_sig = MutationDriverSignal.mutationError;
        }
    }

    void testMutant() {
        import dextool.type : Path;

        assert(!mutp.isNull);
        driver_sig = MutationDriverSignal.mutationError;

        if (test_case_cmd.length != 0 || tc_analyze_builtin.length != 0) {
            try {
                auto tmpdir = createTmpDir(mutp.id);
                if (tmpdir.length == 0)
                    return;
                test_tmp_output = Path(tmpdir).AbsolutePath;
                auto_cleanup.add(test_tmp_output);
            } catch (Exception e) {
                logger.warning(e.msg).collectException;
                return;
            }
        }

        try {
            import dextool.plugin.mutate.backend.watchdog : StaticTime;

            auto watchdog = StaticTime!StopWatch(tester_runtime);

            mut_status = runTester(compile_cmd, test_cmd, test_tmp_output, watchdog, fio);
            driver_sig = MutationDriverSignal.next;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    void testCaseAnalyze() {
        import std.algorithm : splitter, map, filter;
        import std.array : array;
        import std.ascii : newline;
        import std.file : exists;
        import std.path : buildPath;
        import std.process : execute;
        import std.string : strip;

        if (mut_status != Mutation.Status.killed || test_tmp_output.length == 0) {
            driver_sig = MutationDriverSignal.next;
            return;
        }

        driver_sig = MutationDriverSignal.mutationError;

        try {
            auto stdout_ = buildPath(test_tmp_output, stdoutLog);
            auto stderr_ = buildPath(test_tmp_output, stderrLog);

            if (!exists(stdout_) || !exists(stderr_)) {
                logger.warningf("Unable to open %s and %s for test case analyze", stdout_, stderr_);
                return;
            }

            auto gather_tc = new GatherTestCase;

            // the post processer must succeeed for the data to be stored. if
            // is considered a major error that may corrupt existing data if it
            // fails.
            bool success = true;

            if (test_case_cmd.length != 0)
                success = success && externalProgram([test_case_cmd, stdout_, stderr_], gather_tc);
            if (tc_analyze_builtin.length != 0)
                success = success && builtin(fio.getOutputDir, [stdout_,
                        stderr_], tc_analyze_builtin, gather_tc);

            if (success) {
                test_cases = gather_tc;
                driver_sig = MutationDriverSignal.next;
            }
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    void storeResult() {
        import std.algorithm : sort, map;

        driver_sig = MutationDriverSignal.next;

        sw.stop;

        spinSqlQuery!(() {
            db.updateMutation(mutp.id, mut_status, sw.peek, test_cases.failedAsArray);
        });

        logger.infof("%s %s (%s)", mutp.id, mut_status, sw.peek).collectException;
        logger.infof(test_cases.failed.length != 0, `%s killed by [%-(%s, %)]`,
                mutp.id, test_cases.failedAsArray.sort.map!"a.name").collectException;
    }

    void restoreCode() {
        driver_sig = MutationDriverSignal.next;

        // restore the original file.
        try {
            fio.makeOutput(mut_file).write(original_content);
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            // fatal error because being unable to restore a file prohibit
            // future mutations.
            driver_sig = MutationDriverSignal.filesysError;
        }

        if (test_tmp_output.length != 0) {
            import std.file : rmdirRecurse;

            // trusted: test_tmp_output is tested to be valid data.
            () @trusted {
                try {
                    rmdirRecurse(test_tmp_output);
                } catch (Exception e) {
                    logger.info(e.msg).collectException;
                }
            }();
        }
    }

    /// Signal from the ImplMutationDriver to the Driver.
    auto signal() {
        return driver_sig;
    }
}

enum TestDriverSignal {
    stop,
    next,
    allMutantsTested,
    unreliableTestSuite,
    compilationError,
    mutationError,
    timeoutUnchanged,
    sanityCheckFailed,
}

struct TestDriver(ImplT) {
    private enum State {
        none,
        initialize,
        sanityCheck,
        updateAndResetAliveMutants,
        resetOldMutants,
        cleanupTempDirs,
        checkMutantsLeft,
        preCompileSut,
        measureTestSuite,
        preMutationTest,
        mutationTest,
        checkTimeout,
        incrWatchdog,
        resetTimeout,
        done,
        error,
    }

    private {
        State st;
        ImplT impl;
    }

    this(ImplT impl) {
        this.impl = impl;
    }

    bool isRunning() {
        import std.algorithm : among;

        return st.among(State.done, State.error) == 0;
    }

    ExitStatusType status() {
        if (st == State.done)
            return ExitStatusType.Ok;
        else
            return ExitStatusType.Errors;
    }

    void execute() {
        import dextool.fsm : generateActions;

        const auto signal = impl.signal;

        debug auto old_st = st;

        st = nextState(st, signal);

        debug logger.trace(old_st, "->", st, ":", signal).collectException;

        mixin(generateActions!(State, "st", "impl"));
    }

    private static State nextState(const State current, const TestDriverSignal signal) {
        State next_ = current;

        final switch (current) with (State) {
        case none:
            next_ = State.initialize;
            break;
        case initialize:
            if (signal == TestDriverSignal.next)
                next_ = State.sanityCheck;
            break;
        case sanityCheck:
            if (signal == TestDriverSignal.next)
                next_ = State.preCompileSut;
            else if (signal == TestDriverSignal.sanityCheckFailed)
                next_ = State.error;
            break;
        case updateAndResetAliveMutants:
            next_ = resetOldMutants;
            break;
        case resetOldMutants:
            next_ = checkMutantsLeft;
            break;
        case checkMutantsLeft:
            if (signal == TestDriverSignal.next)
                next_ = State.measureTestSuite;
            else if (signal == TestDriverSignal.allMutantsTested)
                next_ = State.done;
            break;
        case preCompileSut:
            if (signal == TestDriverSignal.next)
                next_ = State.updateAndResetAliveMutants;
            else if (signal == TestDriverSignal.compilationError)
                next_ = State.error;
            break;
        case measureTestSuite:
            if (signal == TestDriverSignal.next)
                next_ = State.cleanupTempDirs;
            else if (signal == TestDriverSignal.unreliableTestSuite)
                next_ = State.error;
            break;
        case cleanupTempDirs:
            next_ = preMutationTest;
            break;
        case preMutationTest:
            next_ = State.mutationTest;
            break;
        case mutationTest:
            if (signal == TestDriverSignal.next)
                next_ = State.cleanupTempDirs;
            else if (signal == TestDriverSignal.allMutantsTested)
                next_ = State.checkTimeout;
            else if (signal == TestDriverSignal.mutationError)
                next_ = State.error;
            break;
        case checkTimeout:
            if (signal == TestDriverSignal.timeoutUnchanged)
                next_ = State.done;
            else if (signal == TestDriverSignal.next)
                next_ = State.incrWatchdog;
            break;
        case incrWatchdog:
            next_ = State.resetTimeout;
            break;
        case resetTimeout:
            if (signal == TestDriverSignal.next)
                next_ = State.cleanupTempDirs;
            break;
        case done:
            break;
        case error:
            break;
        }

        return next_;
    }
}

struct ImplTestDriver(alias mutationDriverFactory) {
    import std.traits : ReturnType;
    import dextool.plugin.mutate.backend.watchdog : ProgressivWatchdog;

nothrow:
    DriverData data;

    ProgressivWatchdog prog_wd;
    TestDriverSignal driver_sig;
    ReturnType!mutationDriverFactory mut_driver;
    long last_timeout_mutant_count = long.max;

    this(DriverData data) {
        this.data = data;
    }

    void none() {
    }

    void done() {
        data.autoCleanup.cleanup;
    }

    void error() {
        data.autoCleanup.cleanup;
    }

    void initialize() {
        driver_sig = TestDriverSignal.next;
    }

    void sanityCheck() {
        // #SPC-sanity_check_db_vs_filesys
        import dextool.type : Path;
        import dextool.plugin.mutate.backend.utility : checksum, trustedRelativePath;
        import dextool.plugin.mutate.backend.type : Checksum;

        driver_sig = TestDriverSignal.sanityCheckFailed;

        const(Path)[] files;
        spinSqlQuery!(() { files = data.db.getFiles; });

        bool has_sanity_check_failed;
        for (size_t i; i < files.length;) {
            Checksum db_checksum;
            spinSqlQuery!(() { db_checksum = data.db.getFileChecksum(files[i]); });

            try {
                auto abs_f = AbsolutePath(FileName(files[i]),
                        DirName(cast(string) data.filesysIO.getOutputDir));
                auto f_checksum = checksum(data.filesysIO.makeInput(abs_f).read[]);
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
            driver_sig = TestDriverSignal.sanityCheckFailed;
            logger.error("Detected that one or more file has changed since last analyze where done")
                .collectException;
            logger.error("Either restore the files to the previous state or rerun the analyzer")
                .collectException;
        } else {
            logger.info("Sanity check passed. Files on the filesystem are consistent")
                .collectException;
            driver_sig = TestDriverSignal.next;
        }
    }

    // TODO: refactor. This method is too long.
    void updateAndResetAliveMutants() {
        import core.time : dur;
        import std.algorithm : map;
        import std.datetime.stopwatch : StopWatch;
        import std.path : buildPath;
        import dextool.type : Path;
        import dextool.plugin.mutate.backend.type : TestCase;

        driver_sig = TestDriverSignal.next;

        if (data.conf.mutationTestCaseAnalyze.length == 0
                && data.conf.mutationTestCaseBuiltin.length == 0)
            return;

        AbsolutePath test_tmp_output;
        try {
            auto tmpdir = createTmpDir(0);
            if (tmpdir.length == 0)
                return;
            test_tmp_output = Path(tmpdir).AbsolutePath;
            data.autoCleanup.add(test_tmp_output);
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
            runTester(data.conf.mutationCompile, data.conf.mutationTester,
                    test_tmp_output, watchdog, data.filesysIO);

            auto gather_tc = new GatherTestCase;

            bool success = true;
            if (data.conf.mutationTestCaseAnalyze.length != 0)
                success = success && externalProgram([data.conf.mutationTestCaseAnalyze,
                        stdout_, stderr_], gather_tc);
            if (data.conf.mutationTestCaseBuiltin.length != 0)
                success = success && builtin(data.filesysIO.getOutputDir, [stdout_,
                        stderr_], data.conf.mutationTestCaseBuiltin, gather_tc);

            all_found_tc = gather_tc.foundAsArray;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }

        warnIfConflictingTestCaseIdentifiers(all_found_tc);

        // the test cases before anything has potentially changed.
        Set!string old_tcs;
        spinSqlQuery!(() {
            old_tcs = null;
            foreach (tc; data.db.getDetectedTestCases)
                old_tcs.add(tc.name);
        });

        final switch (data.conf.onRemovedTestCases) with (ConfigMutationTest.RemovedTestCases) {
        case doNothing:
            spinSqlQuery!(() { data.db.addDetectedTestCases(all_found_tc); });
            break;
        case remove:
            spinSqlQuery!(() { data.db.setDetectedTestCases(all_found_tc); });
            break;
        }

        Set!string found_tcs;
        spinSqlQuery!(() {
            found_tcs = null;
            foreach (tc; data.db.getDetectedTestCases)
                found_tcs.add(tc.name);
        });

        printDroppedTestCases(old_tcs, found_tcs);

        const new_test_cases = hasNewTestCases(old_tcs, found_tcs);

        if (new_test_cases && data.conf.onNewTestCases == ConfigMutationTest
                .NewTestCases.resetAlive) {
            logger.info("Resetting alive mutants").collectException;
            resetAliveMutants(data.db);
        }
    }

    void resetOldMutants() {
        import dextool.plugin.mutate.backend.database.type;

        if (data.conf.onOldMutants == ConfigMutationTest.OldMutant.nothing)
            return;

        logger.infof("Resetting the %s oldest mutants", data.conf.oldMutantsNr).collectException;
        OldMutant[] oldest;
        spinSqlQuery!(() {
            oldest = data.db.getOldestMutants(data.mutKind, data.conf.oldMutantsNr);
        });
        foreach (const old; oldest) {
            logger.info("  Last updated ", old.timestamp).collectException;
            spinSqlQuery!(() {
                data.db.updateMutationStatus(old.statusId, Mutation.Status.unknown);
            });
        }
    }

    void cleanupTempDirs() {
        driver_sig = TestDriverSignal.next;
        data.autoCleanup.cleanup;
    }

    void checkMutantsLeft() {
        driver_sig = TestDriverSignal.next;

        auto mutant = spinSqlQuery!(() {
            return data.db.nextMutation(data.mutKind);
        });

        if (mutant.st == NextMutationEntry.Status.done) {
            logger.info("Done! All mutants are tested").collectException;
            driver_sig = TestDriverSignal.allMutantsTested;
        }
    }

    void preCompileSut() {
        driver_sig = TestDriverSignal.compilationError;

        logger.info("Preparing for mutation testing by checking that the program and tests compile without any errors (no mutants injected)")
            .collectException;

        try {
            import std.process : execute;

            const comp_res = execute([cast(string) data.conf.mutationCompile]);

            if (comp_res.status == 0) {
                driver_sig = TestDriverSignal.next;
            } else {
                logger.info(comp_res.output);
                logger.error("Compiler command failed: ", comp_res.status);
            }
        } catch (Exception e) {
            // unable to for example execute the compiler
            logger.error(e.msg).collectException;
        }
    }

    void measureTestSuite() {
        driver_sig = TestDriverSignal.unreliableTestSuite;

        if (data.conf.mutationTesterRuntime.isNull) {
            logger.info("Measuring the time to run the tests: ",
                    data.conf.mutationTester).collectException;
            auto tester = measureTesterDuration(data.conf.mutationTester);
            if (tester.status == ExitStatusType.Ok) {
                // The sampling of the test suite become too unreliable when the timeout is <1s.
                // This is a quick and dirty fix.
                // A proper fix requires an update of the sampler in runTester.
                auto t = tester.runtime < 1.dur!"seconds" ? 1.dur!"seconds" : tester.runtime;
                logger.info("Tester measured to: ", t).collectException;
                prog_wd = ProgressivWatchdog(t);
                driver_sig = TestDriverSignal.next;
            } else {
                logger.error(
                        "Test suite is unreliable. It must return exit status '0' when running with unmodified mutants")
                    .collectException;
            }
        } else {
            prog_wd = ProgressivWatchdog(data.conf.mutationTesterRuntime.get);
            driver_sig = TestDriverSignal.next;
        }
    }

    void preMutationTest() {
        driver_sig = TestDriverSignal.next;
        mut_driver = mutationDriverFactory(data, prog_wd.timeout);
    }

    void mutationTest() {
        if (mut_driver.isRunning) {
            mut_driver.execute();
            driver_sig = TestDriverSignal.stop;
        } else if (mut_driver.stopBecauseError) {
            driver_sig = TestDriverSignal.mutationError;
        } else if (mut_driver.stopMutationTesting) {
            driver_sig = TestDriverSignal.allMutantsTested;
        } else {
            driver_sig = TestDriverSignal.next;
        }
    }

    void checkTimeout() {
        driver_sig = TestDriverSignal.stop;

        auto entry = spinSqlQuery!(() {
            return data.db.timeoutMutants(data.mutKind);
        });

        try {
            if (!data.conf.mutationTesterRuntime.isNull) {
                // the user have supplied a timeout thus ignore this algorithm
                // for increasing the timeout
                driver_sig = TestDriverSignal.timeoutUnchanged;
            } else if (entry.count == 0) {
                driver_sig = TestDriverSignal.timeoutUnchanged;
            } else if (entry.count == last_timeout_mutant_count) {
                // no change between current pool of timeout mutants and the previous
                driver_sig = TestDriverSignal.timeoutUnchanged;
            } else if (entry.count < last_timeout_mutant_count) {
                driver_sig = TestDriverSignal.next;
                logger.info("Mutants with the status timeout: ", entry.count);
            }

            last_timeout_mutant_count = entry.count;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    void incrWatchdog() {
        driver_sig = TestDriverSignal.next;
        prog_wd.incrTimeout;
        logger.info("Increasing timeout to: ", prog_wd.timeout).collectException;
    }

    void resetTimeout() {
        // database is locked
        driver_sig = TestDriverSignal.stop;

        try {
            data.db.resetMutant(data.mutKind, Mutation.Status.timeout, Mutation.Status.unknown);
            driver_sig = TestDriverSignal.next;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    auto signal() {
        return driver_sig;
    }
}

private:

import dextool.plugin.mutate.backend.test_mutant.interface_ : TestCaseReport;
import dextool.plugin.mutate.backend.type : TestCase;
import dextool.set;

/// Run an external program that analyze the output from the test suite for test cases that failed.
bool externalProgram(string[] cmd, TestCaseReport report) nothrow {
    import std.algorithm : copy, splitter, filter, map;
    import std.ascii : newline;
    import std.process : execute;
    import std.string : strip;
    import dextool.plugin.mutate.backend.type : TestCase;

    try {
        // [test_case_cmd, stdout_, stderr_]
        auto p = execute(cmd);
        if (p.status == 0) {
            foreach (tc; p.output.splitter(newline).map!(a => a.strip)
                    .filter!(a => a.length != 0)
                    .map!(a => TestCase(a))) {
                report.reportFailed(tc);
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

    spinSqlQuery!(() {
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
    foreach (tc; new_tcs.byKey) {
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
    auto removed = diff.setToList!string;

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
        import std.algorithm : filter;
        import std.array : array;
        import std.file : rmdirRecurse, exists;

        foreach (ref p; remove_dirs.filter!(a => a.length != 0)) {
            try {
                if (exists(p))
                    rmdirRecurse(p);
                if (!exists(p))
                    p = null;
            } catch (Exception e) {
                logger.info(e.msg).collectException;
            }
        }

        remove_dirs = remove_dirs.filter!(a => a.length != 0).array;
    }
}
