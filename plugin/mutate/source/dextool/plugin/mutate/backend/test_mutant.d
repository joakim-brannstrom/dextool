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
import std.typecons : Nullable, NullableRef;
import std.exception : collectException;

import logger = std.experimental.logger;

import dextool.type : AbsolutePath, ExitStatusType, FileName, DirName;
import dextool.plugin.mutate.backend.database : Database, MutationEntry,
    NextMutationEntry;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.type : MutationKind;

@safe:

/**
 * TODO add nothrow
 *
 * Params:
 *  tester = a program to execute that test the mutant. The mutant is marked as alive if the exit code is 0, otherwise it is dead.
 *  compilep = program to use to compile the SUT + tests after a mutation has been performed.
 *  testerp_runtime = the time it takes to run the tests.
 */
ExitStatusType runTestMutant(ref Database db, MutationKind user_kind, AbsolutePath testerp,
        AbsolutePath compilep, Nullable!Duration testerp_runtime, FilesysIO fio) nothrow {
    import dextool.plugin.mutate.backend.utility : toInternal;

    auto mut_kind = user_kind.toInternal;

    if (db.nextMutation(mut_kind).st == NextMutationEntry.Status.done) {
        logger.info("Done! All mutants are tested").collectException;
        return ExitStatusType.Ok;
    }

    if (compilep.length == 0) {
        logger.error("No compile command specified (--mutant-compile)").collectException;
        return ExitStatusType.Errors;
    }

    // build the SUT before trying to measure the test suite

    // sanity check the compiler command. This should pass
    try {
        import std.process : execute;

        auto comp_res = execute([cast(string) compilep]);
        if (comp_res.status != 0) {
            logger.error("Compiler command must succeed: ", comp_res.output);
            return ExitStatusType.Errors;
        }
    }
    catch (Exception e) {
        // unable to for example execute the compiler
        logger.error(e.msg).collectException;
        return ExitStatusType.Errors;
    }

    Duration tester_runtime;
    if (testerp_runtime.isNull) {
        logger.info("Measuring the time to run the tester: ", testerp).collectException;
        auto tester = measureTesterDuration(testerp);
        if (tester.status.ExitStatusType != ExitStatusType.Ok) {
            logger.errorf(
                    "Test suite is unreliable. It must return exit status '0' when running with unmodified mutants",
                    testerp).collectException;
            return ExitStatusType.Errors;
        }
        logger.info("Tester measured to: ", tester.runtime).collectException;
        tester_runtime = tester.runtime;
    } else {
        tester_runtime = testerp_runtime.get;
    }

    while (true) {
        import std.datetime.stopwatch : StopWatch, AutoStart;

        auto impl = ImplDriver(fio, () @trusted{ return &db; }(), mut_kind,
                compilep, testerp, tester_runtime);

        auto mut_driver = MutationTestDriver!(ImplDriver*)(() @trusted{
            return &impl;
        }());

        while (mut_driver.isRunning) {
            mut_driver.execute();
        }

        if (mut_driver.stopBecauseError)
            return ExitStatusType.Errors;
        else if (mut_driver.stopMutationTesting)
            return ExitStatusType.Ok;
    }
}

private:

/** Run the test suite to verify a mutation.
 *
 * Params:
 *  p = ?
 *  timeout = timeout threshold.
 */
Mutation.Status runTester(AbsolutePath compile_p, AbsolutePath tester_p,
        Duration original_runtime, double timeout_scalefactor, FilesysIO fio) nothrow {
    import core.thread : Thread;
    import core.time : dur;
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

        import dextool.plugin.mutate.backend.watchdog : StaticTime;

        auto watchdog = StaticTime!StopWatch((1L + (cast(long)(
                original_runtime.total!"msecs" * timeout_scalefactor))).dur!"msecs");

        rval = Mutation.Status.timeout;
        while (watchdog.isOk) {
            auto res = tryWait(p);
            if (res.terminated) {
                if (res.status == 0)
                    rval = Mutation.Status.alive;
                else
                    rval = Mutation.Status.killed;
                break;
            }

            // trusted: a hard coded value is used, no user input.
            () @trusted{ Thread.sleep(1.dur!"msecs"); }();
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

enum DriverSignal {
    stop,
    next,
    /// All mutants are tested. Stopping mutation testing
    allMutantsTested,
    /// Filesystem error. Stopping all mutation testing
    filesysError,
    /// An error for a single mutation. It skips the mutant.
    mutationError,
}

/** Drive the control flow when testing a mutant.
 *
 * The architecture assume that there will be behavior changes therefore a
 * strict FSM that separate the context, action and next_state.
 *
 * The intention is to separate the control flow from the implementation of the
 * actions that are done when mutation testing.
 *
 * # Signals
 * stop: stay in the current state
 * next: advance to the next state
 * allMutantsTested: no more mutants to test.
 * filesysError: an error occured when interacting with the filesystem (fatal)
 * mutationError: an error occured when testing a mutant (not fatal)
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

    this(ImplT cb) {
        this.impl = cb;
        this.st = State.none;
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
        auto signal = impl.signal;

        st = nextState(st, signal);

        debug logger.trace(st).collectException;

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
            break;
        case State.noResultRestoreCode:
            impl.cleanup;
            break;
        case State.noResult:
            break;
        }
    }

    private static State nextState(State current, DriverSignal signal) {
        auto next_ = current;

        final switch (current) {
        case State.none:
            next_ = State.initialize;
            break;
        case State.initialize:
            if (signal == DriverSignal.next)
                next_ = State.mutateCode;
            break;
        case State.mutateCode:
            if (signal == DriverSignal.next)
                next_ = State.testMutant;
            else if (signal == DriverSignal.allMutantsTested)
                next_ = State.allMutantsTested;
            else if (signal == DriverSignal.filesysError)
                next_ = State.filesysError;
            break;
        case State.testMutant:
            if (signal == DriverSignal.next)
                next_ = State.restoreCode;
            else if (signal == DriverSignal.mutationError)
                next_ = State.noResultRestoreCode;
            break;
        case State.restoreCode:
            if (signal == DriverSignal.next)
                next_ = State.storeResult;
            else if (signal == DriverSignal.filesysError)
                next_ = State.filesysError;
            break;
        case State.storeResult:
            if (signal == DriverSignal.next)
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
struct ImplDriver {
    import core.time : dur;
    import std.datetime.stopwatch : StopWatch;

nothrow:

    immutable wait_for_lock = 100.dur!"msecs";

    FilesysIO fio;
    NullableRef!Database db;

    StopWatch sw;
    DriverSignal driver_sig;

    Nullable!MutationEntry mutp;
    AbsolutePath mut_file;
    const(ubyte)[] original_content;

    // change to const
    Mutation.Kind[] mut_kind;

    AbsolutePath compile_cmd;
    AbsolutePath test_cmd;
    Duration tester_runtime;

    Mutation.Status mut_status;

    this(FilesysIO fio, Database* db, Mutation.Kind[] mut_kind,
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
        driver_sig = DriverSignal.next;
    }

    void mutateCode() {
        import core.thread : Thread;
        import std.random : uniform;
        import dextool.plugin.mutate.backend.generate_mutant : generateMutant,
            GenerateMutantResult;

        driver_sig = DriverSignal.stop;

        auto next_m = db.nextMutation(mut_kind);
        if (next_m.st == NextMutationEntry.Status.done) {
            logger.info("Done! All mutants are tested").collectException;
            driver_sig = DriverSignal.allMutantsTested;
            return;
        } else if (next_m.st == NextMutationEntry.Status.queryError) {
            () @trusted nothrow{
                Thread.sleep(wait_for_lock + uniform(0, 200).dur!"msecs").collectException;
            }();
            return;
        } else {
            mutp = next_m.entry;
        }

        try {
            mut_file = AbsolutePath(FileName(mutp.file), DirName(fio.getRestrictDir));

            // must duplicate because the buffer is memory mapped thus it can change
            original_content = fio.makeInput(mut_file).read.dup;
        }
        catch (Exception e) {
            logger.error(e.msg).collectException;
            driver_sig = DriverSignal.filesysError;
            return;
        }

        if (original_content.length == 0) {
            logger.warning("Unable to read ", mut_file).collectException;
            driver_sig = DriverSignal.filesysError;
            return;
        }

        // mutate
        auto mut_res = GenerateMutantResult(ExitStatusType.Errors);
        try {
            auto fout = fio.makeOutput(mut_file);
            mut_res = generateMutant(db.get, mutp, original_content, fout);

            driver_sig = DriverSignal.next;

            if (mut_res.status == ExitStatusType.Ok) {
                logger.infof("%s Mutate from '%s' to '%s' in %s:%s:%s", mutp.id,
                        mut_res.from, mut_res.to, mut_file, mutp.sloc.line, mutp.sloc.column);
            }
        }
        catch (Exception e) {
            logger.warning(e.msg).collectException;
            driver_sig = DriverSignal.filesysError;
        }
    }

    void testMutant() {
        assert(!mutp.isNull);
        driver_sig = DriverSignal.mutationError;

        try {
            // TODO is 100% over the original runtime a resonable timeout?
            mut_status = runTester(compile_cmd, test_cmd, tester_runtime, 2.0, fio);
            driver_sig = DriverSignal.next;
        }
        catch (Exception e) {
            logger.warning(e.msg).collectException;
        }

        sw.stop;
    }

    void storeResult() {
        driver_sig = DriverSignal.stop;

        try {
            db.updateMutation(mutp.id, mut_status, sw.peek);
            driver_sig = DriverSignal.next;
            logger.infof("%s Mutant is %s (%s)", mutp.id, mut_status, sw.peek);
        }
        catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    void cleanup() {
        driver_sig = DriverSignal.next;

        // restore the original file.
        try {
            fio.makeOutput(mut_file).write(original_content);
        }
        catch (Exception e) {
            logger.error(e.msg).collectException;
            // fatal error because being unable to restore a file prohibit
            // future mutations.
            driver_sig = DriverSignal.filesysError;
        }
    }

    /// Signal from the ImplDriver to the Driver.
    auto signal() {
        return driver_sig;
    }
}
