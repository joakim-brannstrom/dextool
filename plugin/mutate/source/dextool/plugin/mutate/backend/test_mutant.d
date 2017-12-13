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
import std.typecons : Nullable;
import std.exception : collectException;

import logger = std.experimental.logger;

import dextool.type : AbsolutePath, ExitStatusType;
import dextool.plugin.mutate.backend.database : Database;
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
    if (compilep.length == 0) {
        logger.error("No compile command specified (--mutant-compile)").collectException;
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

    import dextool.plugin.mutate.backend.type : Mutation;
    import dextool.plugin.mutate.backend.utility : toInternal;
    import dextool.plugin.mutate.backend.generate_mutant : generateMutant,
        GenerateMutantResult;

    auto mut_kind = user_kind.toInternal;
    // when it reaches 100 terminate. there are too many mutations that result
    // in the test or compiler _crashing_.
    int unknown_mutant_cnt;
    immutable unknown_mutant_max = 100;

    while (unknown_mutant_cnt < unknown_mutant_max) {
        import std.datetime.stopwatch : StopWatch, AutoStart;

        auto mutation_sw = StopWatch(AutoStart.yes);

        // get mutant
        auto mutp = db.nextMutation(mut_kind);
        if (mutp.isNull) {
            logger.info("Done! All mutants are tested").collectException;
            return ExitStatusType.Ok;
        }

        // get content
        ubyte[] content;
        try {
            content = fio.makeInput(mutp.file).read;
        }
        catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
        if (content.length == 0) {
            logger.warning("Unable to read ", mutp.file).collectException;
            continue;
        }

        // mutate
        auto mut_res = GenerateMutantResult(ExitStatusType.Errors);
        try {
            auto fout = fio.makeOutput(mutp.file);
            mut_res = generateMutant(db, mutp, content, fout);
        }
        catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
        if (mut_res.status == ExitStatusType.Ok) {
            logger.infof("%s Mutate from '%s' to '%s' in %s:%s:%s", mutp.id,
                    mut_res.from, mut_res.to, mutp.file, mutp.sloc.line, mutp.sloc.column)
                .collectException;

            // test mutant
            try {
                // TODO is 50% over the original runtime a resonable timeout?
                auto mut_status = runTester(compilep, testerp, tester_runtime, 1.5, fio);

                mutation_sw.stop;
                db.updateMutation(mutp.id, mut_status, mutation_sw.peek);
                logger.infof("%s Mutant is %s (%s)", mutp.id, mut_status, mutation_sw.peek);
                if (mut_status == Mutation.Status.unknown)
                    ++unknown_mutant_cnt;
                else
                    unknown_mutant_cnt = 0;
            }
            catch (Exception e) {
                logger.warning(e.msg).collectException;
            }
        }

        // restore the original file.
        try {
            fio.makeOutput(mutp.file).write(content);
        }
        catch (Exception e) {
            logger.error(e.msg).collectException;
            // fatal error because being unable to restore a file prohibit
            // future mutations.
            return ExitStatusType.Errors;
        }
    }

    if (unknown_mutant_cnt == unknown_mutant_max)
        logger.error("Terminated early. Too many unknown mutants (%s)",
                unknown_mutant_cnt).collectException;

    return ExitStatusType.Errors;
}

private:

/** Run the test suite to verify a mutation.
 *
 * Params:
 *  p = ?
 *  timeout = timeout threshold.
 */
Mutation.Status runTester(AbsolutePath compile_p, AbsolutePath tester_p,
        Duration original_runtime, double timeout, FilesysIO fio) nothrow {
    import core.thread : Thread;
    import core.time : dur;
    import std.algorithm : among;
    import std.datetime : Clock;
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

        auto end_t = Clock.currTime + (1L + (cast(long)(original_runtime.total!"msecs" * timeout)))
            .dur!"msecs";

        rval = Mutation.Status.timeout;
        while (Clock.currTime < end_t) {
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
