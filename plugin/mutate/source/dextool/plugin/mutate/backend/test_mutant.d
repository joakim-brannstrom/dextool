/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.test_mutant;

import core.time : Duration;
import std.typecons : Nullable, NullableRef, nullableRef;
import std.exception : collectException;

import logger = std.experimental.logger;

import dextool.type : AbsolutePath, ExitStatusType, FileName, DirName;
import dextool.plugin.mutate.backend.database : Database, MutationEntry,
    NextMutationEntry;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.type : MutationKind;

@safe:

/** Test mutations.
 *
 * Params:
 *  tester = a program to execute that test the mutant. The mutant is marked as alive if the exit code is 0, otherwise it is dead.
 *  compilep = program to use to compile the SUT + tests after a mutation has been performed.
 *  testerp_runtime = the time it takes to run the tests.
 */
ExitStatusType runTestMutant(ref Database db, const MutationKind[] user_kind,
        AbsolutePath testerp, AbsolutePath compilep,
        Nullable!Duration testerp_runtime, FilesysIO fio) nothrow {
    import dextool.plugin.mutate.backend.utility : toInternal;

    auto mutationFactory(DriverData data, Duration test_base_timeout) @safe {
        static class Rval {
            ImplMutationDriver impl;
            MutationTestDriver!(ImplMutationDriver*) driver;

            this(DriverData d, Duration test_base_timeout) {
                this.impl = ImplMutationDriver(d.filesysIO, d.db, d.mutKind,
                        d.compilerProgram, d.testProgram, test_base_timeout);

                this.driver = MutationTestDriver!(ImplMutationDriver*)(() @trusted{
                    return &impl;
                }());
            }

            alias driver this;
        }

        return new Rval(data, test_base_timeout);
    }

    // trusted because the lifetime of the database is guaranteed to outlive any instances in this scope
    auto db_ref = () @trusted{ return nullableRef(&db); }();

    auto driver_data = DriverData(db_ref, fio, user_kind.toInternal, compilep,
            testerp, testerp_runtime);

    auto test_driver_impl = ImplTestDriver!mutationFactory(driver_data);
    auto test_driver_impl_ref = () @trusted{
        return nullableRef(&test_driver_impl);
    }();
    auto test_driver = TestDriver!(typeof(test_driver_impl_ref))(test_driver_impl_ref);

    while (test_driver.isRunning) {
        test_driver.execute;
    }

    return test_driver.status;
}

private:

struct DriverData {
    NullableRef!Database db;
    FilesysIO filesysIO;
    Mutation.Kind[] mutKind;
    AbsolutePath compilerProgram;
    AbsolutePath testProgram;
    Nullable!Duration testProgramTimeout;
}

/** Run the test suite to verify a mutation.
 *
 * Params:
 *  p = ?
 *  timeout = timeout threshold.
 */
Mutation.Status runTester(WatchdogT)(AbsolutePath compile_p,
        AbsolutePath tester_p, WatchdogT watchdog, FilesysIO fio) nothrow {
    import core.thread : Thread;
    import std.algorithm : among;
    import std.datetime.stopwatch : StopWatch;
    import dextool.plugin.mutate.backend.linux_process : spawnSession, tryWait,
        kill, wait;
    import std.stdio : File;
    import core.sys.posix.signal : SIGKILL;

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
    }
    catch (Exception e) {
        logger.warning(e.msg).collectException;
    }

    try {
        auto p = spawnSession([cast(string) tester_p]);
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

            import core.time : dur;

            // trusted: a hard coded value is used, no user input.
            () @trusted{ Thread.sleep(10.dur!"msecs"); }();
        }
    }
    catch (Exception e) {
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
auto measureTesterDuration(AbsolutePath p) nothrow {
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
    }
    catch (Exception e) {
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

/** Drive the control flow when testing a mutant.
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

        return st.among(State.done, State.allMutantsTested, State.filesysError, State.noResult) == 0;
    }

    bool stopBecauseError() {
        return st == State.filesysError;
    }

    /// Returns: true when the mutation testing should be stopped
    bool stopMutationTesting() {
        import std.algorithm : among;

        return st.among(State.allMutantsTested, State.filesysError) != 0;
    }

    void execute() {
        const auto signal = impl.signal;

        debug auto old_st = st;

        st = nextState(st, signal);

        debug logger.trace(old_st, "->", st, ":", signal).collectException;

        final switch (st) {
        case State.none:
            break;
        case State.initialize:
            impl.initialize;
            break;
        case State.mutateCode:
            impl.mutateCode;
            break;
        case State.testMutant:
            impl.testMutant;
            break;
        case State.restoreCode:
            impl.cleanup;
            break;
        case State.storeResult:
            impl.storeResult;
            break;
        case State.done:
            break;
        case State.allMutantsTested:
            break;
        case State.filesysError:
            logger.warning("Filesystem error").collectException;
            break;
        case State.noResultRestoreCode:
            impl.cleanup;
            break;
        case State.noResult:
            break;
        }
    }

    private static State nextState(const State current, const MutationDriverSignal signal) {
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

nothrow:

    FilesysIO fio;
    NullableRef!Database db;

    StopWatch sw;
    MutationDriverSignal driver_sig;

    Nullable!MutationEntry mutp;
    AbsolutePath mut_file;
    const(ubyte)[] original_content;

    // change to const
    Mutation.Kind[] mut_kind;

    AbsolutePath compile_cmd;
    AbsolutePath test_cmd;
    Duration tester_runtime;

    Mutation.Status mut_status;

    this(FilesysIO fio, NullableRef!Database db, Mutation.Kind[] mut_kind,
            AbsolutePath compile_cmd, AbsolutePath test_cmd, Duration tester_runtime) {
        this.fio = fio;
        this.db = db;
        this.mut_kind = mut_kind;
        this.compile_cmd = compile_cmd;
        this.test_cmd = test_cmd;
        this.tester_runtime = tester_runtime;
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

        auto next_m = db.nextMutation(mut_kind);
        if (next_m.st == NextMutationEntry.Status.done) {
            logger.info("Done! All mutants are tested").collectException;
            driver_sig = MutationDriverSignal.allMutantsTested;
            return;
        } else if (next_m.st == NextMutationEntry.Status.queryError) {
            // the database is locked. It will automatically sleep and continue.
            return;
        } else {
            mutp = next_m.entry;
        }

        try {
            mut_file = AbsolutePath(FileName(mutp.file), DirName(fio.getOutputDir));

            // must duplicate because the buffer is memory mapped thus it can change
            original_content = fio.makeInput(mut_file).read.dup;
        }
        catch (Exception e) {
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

            driver_sig = MutationDriverSignal.next;

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
                logger.infof("%s Mutate from '%s' to '%s' in %s:%s:%s", mutp.id,
                        mut_res.from, mut_res.to, mut_file, mutp.sloc.line, mutp.sloc.column);
                break;
            }
        }
        catch (Exception e) {
            logger.warning(e.msg).collectException;
            driver_sig = MutationDriverSignal.mutationError;
        }
    }

    void testMutant() {
        assert(!mutp.isNull);
        driver_sig = MutationDriverSignal.mutationError;

        try {
            import dextool.plugin.mutate.backend.watchdog : StaticTime;

            auto watchdog = StaticTime!StopWatch(tester_runtime);

            mut_status = runTester(compile_cmd, test_cmd, watchdog, fio);
            driver_sig = MutationDriverSignal.next;
        }
        catch (Exception e) {
            logger.warning(e.msg).collectException;
        }

        sw.stop;
    }

    void storeResult() {
        import dextool.plugin.mutate.backend.mutation_type : broadcast;

        driver_sig = MutationDriverSignal.stop;

        try {
            auto bcast = broadcast(mutp.mp.mutations[0].kind);

            db.updateMutationBroadcast(mutp.id, mut_status, sw.peek, bcast);
            driver_sig = MutationDriverSignal.next;
            logger.infof("%s Mutant is %s (%s)", mutp.id, mut_status, sw.peek);
        }
        catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    void cleanup() {
        driver_sig = MutationDriverSignal.next;

        // restore the original file.
        try {
            fio.makeOutput(mut_file).write(original_content);
        }
        catch (Exception e) {
            logger.error(e.msg).collectException;
            // fatal error because being unable to restore a file prohibit
            // future mutations.
            driver_sig = MutationDriverSignal.filesysError;
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
        const auto signal = impl.signal;

        debug auto old_st = st;

        st = nextState(st, signal);

        debug logger.trace(old_st, "->", st, ":", signal).collectException;

        final switch (st) with (State) {
        case none:
            break;
        case initialize:
            impl.initialize;
            break;
        case sanityCheck:
            impl.sanityCheck;
            break;
        case checkMutantsLeft:
            impl.checkMutantsLeft;
            break;
        case preCompileSut:
            impl.compileProgram;
            break;
        case measureTestSuite:
            impl.measureTestSuite;
            break;
        case preMutationTest:
            impl.preMutationTest;
            break;
        case mutationTest:
            impl.testMutant;
            break;
        case checkTimeout:
            impl.checkTimeout;
            break;
        case incrWatchdog:
            impl.incrWatchdog;
            break;
        case resetTimeout:
            impl.resetTimeout;
            break;
        case done:
            break;
        case error:
            break;
        }
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
                next_ = State.checkMutantsLeft;
            else if (signal == TestDriverSignal.sanityCheckFailed)
                next_ = State.error;
            break;
        case checkMutantsLeft:
            if (signal == TestDriverSignal.next)
                next_ = State.preCompileSut;
            else if (signal == TestDriverSignal.allMutantsTested)
                next_ = State.done;
            break;
        case preCompileSut:
            if (signal == TestDriverSignal.next)
                next_ = State.measureTestSuite;
            else if (signal == TestDriverSignal.compilationError)
                next_ = State.error;
            break;
        case measureTestSuite:
            if (signal == TestDriverSignal.next)
                next_ = State.preMutationTest;
            else if (signal == TestDriverSignal.unreliableTestSuite)
                next_ = State.error;
            break;
        case preMutationTest:
            next_ = State.mutationTest;
            break;
        case mutationTest:
            if (signal == TestDriverSignal.next)
                next_ = State.preMutationTest;
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
                next_ = State.preMutationTest;
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
    import dextool.plugin.mutate.backend.watchdog : ProgressivWatchdog;
    import std.traits : ReturnType;

nothrow:
    DriverData data;

    ProgressivWatchdog prog_wd;
    TestDriverSignal driver_sig;
    ReturnType!mutationDriverFactory mut_driver;
    long last_timeout_mutant_count = long.max;

    this(DriverData data) {
        this.data = data;
    }

    void initialize() {
        driver_sig = TestDriverSignal.next;
    }

    void sanityCheck() {
        // #SPC-plugin_mutate_sanity_check_db_vs_filesys
        import dextool.type : Path;
        import dextool.plugin.mutate.backend.utility : checksum,
            trustedRelativePath;
        import dextool.plugin.mutate.backend.type : Checksum;

        const(Path)[] files;
        try {
            files = data.db.getFiles;
        }
        catch (Exception e) {
            // assume the database is locked thus need to retry
            driver_sig = TestDriverSignal.stop;
            logger.trace(e.msg).collectException;
            return;
        }

        bool has_sanity_check_failed;
        for (size_t i; i < files.length;) {
            Checksum db_checksum;
            try {
                db_checksum = data.db.getFileChecksum(files[i]);
            }
            catch (Exception e) {
                // the database is locked
                logger.trace(e.msg).collectException;
                // retry
                continue;
            }

            try {
                auto abs_f = AbsolutePath(FileName(files[i]),
                        DirName(cast(string) data.filesysIO.getOutputDir));
                auto f_checksum = checksum(data.filesysIO.makeInput(abs_f).read[]);
                if (db_checksum != f_checksum) {
                    logger.errorf("Mismatch between the file on the filesystem and the analyze of '%s'",
                            abs_f);
                    has_sanity_check_failed = true;
                }
            }
            catch (Exception e) {
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
            driver_sig = TestDriverSignal.next;
        }
    }

    void checkMutantsLeft() {
        driver_sig = TestDriverSignal.next;

        if (data.db.nextMutation(data.mutKind).st == NextMutationEntry.Status.done) {
            logger.info("Done! All mutants are tested").collectException;
            driver_sig = TestDriverSignal.allMutantsTested;
        }
    }

    void compileProgram() {
        driver_sig = TestDriverSignal.compilationError;

        try {
            import std.process : execute;

            auto comp_res = execute([cast(string) data.compilerProgram]);
            if (comp_res.status == 0) {
                driver_sig = TestDriverSignal.next;
            } else {
                logger.error("Compiler command failed: ", comp_res.output);
            }
        }
        catch (Exception e) {
            // unable to for example execute the compiler
            logger.error(e.msg).collectException;
        }
    }

    void measureTestSuite() {
        driver_sig = TestDriverSignal.unreliableTestSuite;

        if (data.testProgramTimeout.isNull) {
            logger.info("Measuring the time to run the tests: ", data.testProgram).collectException;
            auto tester = measureTesterDuration(data.testProgram);
            if (tester.status == ExitStatusType.Ok) {
                logger.info("Tester measured to: ", tester.runtime).collectException;
                prog_wd = ProgressivWatchdog(tester.runtime);
                driver_sig = TestDriverSignal.next;
            } else {
                logger.error(
                        "Test suite is unreliable. It must return exit status '0' when running with unmodified mutants")
                    .collectException;
            }
        } else {
            prog_wd = ProgressivWatchdog(data.testProgramTimeout.get);
            driver_sig = TestDriverSignal.next;
        }
    }

    void preMutationTest() {
        mut_driver = mutationDriverFactory(data, prog_wd.timeout);
    }

    void testMutant() {
        driver_sig = TestDriverSignal.next;

        if (mut_driver.isRunning) {
            mut_driver.execute();
            driver_sig = TestDriverSignal.stop;
        } else if (mut_driver.stopBecauseError) {
            driver_sig = TestDriverSignal.mutationError;
        } else if (mut_driver.stopMutationTesting) {
            driver_sig = TestDriverSignal.allMutantsTested;
        }
    }

    void checkTimeout() {
        // the database is locked
        driver_sig = TestDriverSignal.stop;

        try {
            auto entry = data.db.timeoutMutants(data.mutKind);

            if (!data.testProgramTimeout.isNull) {
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
        }
        catch (Exception e) {
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
        }
        catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    auto signal() {
        return driver_sig;
    }
}
