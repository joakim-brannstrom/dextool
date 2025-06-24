/**
Copyright: Copyright (c) Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.test_mutant.schemata.test;

import logger = std.experimental.logger;
import std.algorithm : min, max;
import std.array : array;
import std.conv : to;
import std.datetime : dur, Duration;
import std.exception : collectException;
import std.sumtype;
import std.typecons : Tuple, tuple;

import my.actor;
import my.container.vector;
import my.gc.refc;
import my.named_type;
import proc : DrainElement;

import dextool.plugin.mutate.backend.test_mutant.common;
import dextool.plugin.mutate.backend.test_mutant.schemata : InjectIdResult;
import dextool.plugin.mutate.backend.test_mutant.test_cmd_runner : TestRunner;
import dextool.plugin.mutate.backend.test_mutant.timeout : TimeoutConfig;
import dextool.plugin.mutate.backend.type : TestCase;
import dextool.plugin.mutate.type : TestCaseAnalyzeBuiltin, ShellCommand;

@safe:

/// Round robin scheduling of mutants for testing from the worker pool.
struct ScheduleTest {
    TestMutantActor.Address[] testers;
    Vector!size_t free;

    this(TestMutantActor.Address[] testers) {
        this.testers = testers;
        foreach (size_t i; 0 .. testers.length)
            free.put(i);
    }

    /// Returns: if the tester is full, no worker used.
    bool full() @safe pure nothrow const @nogc {
        return testers.length == free.length;
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

    void configure(TimeoutConfig conf) {
        foreach (a; testers)
            send(a, conf);
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
                    auto analyze = ctx.state.borrow!(a => a.analyzer.analyze(testCmd.key,
                            testCmd.value));

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
        try {
            auto env = ctx.state.borrow!((ref a) { return a.runner.getDefaultEnv; });
            env[schemataMutantEnvKey] = id.injectId.to!string;

            auto res = ctx.state.borrow!((ref a) {
                return runTester(a.runner, env);
            });
            rval.result.id = id.statusId;
            rval.result.status = res.status;
            rval.result.exitStatus = res.exitStatus;
            rval.result.testCmds = res.output.byKey.array;

            if (!ctx.state.borrow!(a => a.analyzer.empty))
                rval = analyzeForTestCase(rval, res.output);

            rval.testTime = sw.peek;
        } catch (Exception e) {
        }
        return rval;
    }

    static void doConf(ref Ctx ctx, TimeoutConfig conf) @safe {
        ctx.state.borrow!((ref a) { a.runner.timeout = conf.value; });
    }

    self.name = "testMutant";
    return impl(self, st, &run, &doConf);
}
