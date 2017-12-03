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

    import dextool.plugin.mutate.backend.type : Mutation;
    import dextool.plugin.mutate.backend.utility : toInternal;
    import dextool.plugin.mutate.backend.generate_mutant : generateMutant,
        GenerateMutantResult;

    auto mut_kind = user_kind.toInternal;

    while (true) {
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
            logger.infof("%s Mutate from '%s' to '%s' in %s", mutp.id,
                    mut_res.from, mut_res.to, mutp.file).collectException;
        } else {
            continue;
        }

        // test mutant
        // TODO is 50% over the original runtime a resonable timeout?
        auto res = runTester(compilep, testerp, tester_runtime, 1.5, fio);

        // save test result of the mutation
        try {
            Mutation.Status mut_status;
            final switch (res) with (TesterResult) {
            case timeout:
                mut_status = Mutation.Status.dead;
                break;
            case killedMutant:
                mut_status = Mutation.Status.dead;
                break;
            case aliveMutant:
                mut_status = Mutation.Status.alive;
                break;
            }

            db.updateMutation(mutp.id, mut_status);
            logger.infof("%s Mutant is %s", mutp.id, mut_status);
        }
        catch (Exception e) {
            logger.warning(e.msg).collectException;
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
}

private:

enum TesterResult {
    /// the tester timeout. Up to the user of this value if it counts as killing.
    timeout,
    ///
    killedMutant,
    ///
    aliveMutant,
}

/**
 *
 * Params:
 *  p = ?
 *  timeout = timeout threshold.
 */
TesterResult runTester(AbsolutePath compile_p, AbsolutePath tester_p,
        Duration original_runtime, double timeout, FilesysIO fio) nothrow {
    import core.thread : Thread;
    import core.time : dur;
    import std.datetime : Clock;
    import std.process : spawnProcess, tryWait, kill, wait;

    auto rval = TesterResult.timeout;

    try {
        auto dev_null = fio.getDevNull;
        auto stdin = fio.getStdin;

        auto comp_res = spawnProcess(cast(string) compile_p, stdin, dev_null, dev_null).wait;
        if (comp_res != 0)
            return TesterResult.killedMutant;

        auto p = spawnProcess(cast(string) tester_p, stdin, dev_null, dev_null);
        // trusted: killing the process started in this scope
        void cleanup() @trusted {
            import core.sys.posix.signal : SIGKILL;

            if (rval == TesterResult.timeout) {
                p.kill(SIGKILL);
                p.wait;
            }
        }

        scope (exit)
            cleanup;

        auto end_t = Clock.currTime + (1L + (cast(long)(original_runtime.total!"msecs" * timeout)))
            .dur!"msecs";

        while (Clock.currTime < end_t) {
            auto res = tryWait(p);
            if (res.terminated) {
                if (res.status == 0)
                    rval = TesterResult.aliveMutant;
                else
                    rval = TesterResult.killedMutant;
                break;
            }

            // trusted: a hard coded value is used, no user input.
            () @trusted{ Thread.sleep(1.dur!"msecs"); }();
        }
    }
    catch (Exception e) {
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
