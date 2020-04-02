/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

A runner that can execute all the users test commands. These can be either
manually specified or automatically detected.
*/
module dextool.plugin.mutate.backend.test_mutant.test_cmd_runner;

import logger = std.experimental.logger;
import std.algorithm : filter, map;
import std.array : appender, Appender, empty, array;
import std.datetime : Duration, dur, Clock;
import std.exception : collectException;
import std.format : format;
import std.parallelism : TaskPool, Task, task;
import std.random : randomCover;
import std.range : take;
import std.typecons : Tuple;

import process;

import dextool.plugin.mutate.type : ShellCommand;
import dextool.type;

version (unittest) {
    import unit_threaded.assertions;
}

@safe:

struct TestRunner {
    private {
        alias TestTask = Task!(spawnRunTest, string[], Duration, string[string], Signal);
        TaskPool pool;
        Duration timeout_;

        Signal earlyStopSignal;

        /// Commands that execute the test cases.
        alias TestCmd = Tuple!(ShellCommand, "cmd", double, "kills");
        TestCmd[] commands;
        long nrOfRuns;
    }

    /// Environment to set when executing either binaries or the command.
    string[string] env;

    static auto make(int poolSize) {
        return TestRunner(poolSize);
    }

    this(int poolSize_) {
        this.poolSize(poolSize_);
        this.earlyStopSignal = new Signal(false);
    }

    ~this() {
        pool.stop;
    }

    /** Stop executing tests as soon as one detects a failure.
     *
     * This lose some information about the test cases but mean that mutation
     * testing overall is executing faster.
     */
    void useEarlyStop(bool v) @safe nothrow {
        this.earlyStopSignal = new Signal(v);
    }

    bool empty() @safe pure nothrow const @nogc {
        return commands.length == 0;
    }

    void poolSize(const int s) @safe {
        if (pool !is null) {
            pool.stop;
        }
        if (s == 0) {
            pool = new TaskPool;
        } else {
            pool = new TaskPool(s);
        }
        pool.isDaemon = true;
    }

    void timeout(Duration timeout) pure nothrow @nogc {
        this.timeout_ = timeout;
    }

    void put(ShellCommand sh) pure nothrow {
        commands ~= TestCmd(sh, 0);
    }

    void put(ShellCommand[] sh) pure nothrow {
        foreach (a; sh)
            commands ~= TestCmd(a, 0);
    }

    TestResult run(string[string] localEnv = null) {
        return this.run(timeout_, localEnv);
    }

    TestResult run(Duration timeout, string[string] localEnv = null) {
        import core.thread : Thread;
        import core.time : dur;
        import std.range : enumerate;

        static TestTask* findDone(ref TestTask*[] tasks) {
            bool found;
            size_t idx;
            foreach (t; tasks.enumerate.filter!(a => a.value.done)) {
                idx = t.index;
                found = true;
                break;
            }

            if (found) {
                auto t = tasks[idx];
                tasks[idx] = tasks[$ - 1];
                tasks = tasks[0 .. $ - 1];
                return t;
            }
            return null;
        }

        void processDone(TestTask* t, ref TestResult result, ref Appender!(DrainElement[]) output) {
            auto res = t.yieldForce;
            final switch (res.status) {
            case RunResult.Status.normal:
                if (result.status == TestResult.Status.passed && res.exitStatus != 0) {
                    result.status = TestResult.Status.failed;
                }
                if (res.exitStatus != 0) {
                    incrCmdKills(res.cmd);
                }
                output.put(res.output);
                break;
            case RunResult.Status.timeout:
                result.status = TestResult.Status.timeout;
                break;
            case RunResult.Status.error:
                result.status = TestResult.Status.error;
                break;
            }
        }

        auto env_ = env;
        foreach (kv; localEnv.byKeyValue) {
            env_[kv.key] = kv.value;
        }

        const reorderWhen = 10;

        scope (exit)
            nrOfRuns++;
        if (nrOfRuns == 0) {
            commands = commands.randomCover.array;
        } else if (nrOfRuns % reorderWhen == 0) {
            // use a forget factor to make the order re-arrange over time
            // if the "best" test case change.
            foreach (ref a; commands) {
                a.kills = a.kills * 0.9;
            }

            import std.algorithm : sort;

            // use those that kill the most first
            commands = commands.sort!((a, b) => a.kills > b.kills).array;
            logger.infof("Update test command order: %(%s, %)",
                    commands.take(reorderWhen).map!(a => format("%s:%.2f", a.cmd, a.kills)));
        }

        earlyStopSignal.reset;
        TestTask*[] tasks = startTests(timeout, env_);
        TestResult rval;
        auto output = appender!(DrainElement[])();
        while (!tasks.empty) {
            auto t = findDone(tasks);
            if (t !is null) {
                processDone(t, rval, output);
                .destroy(t);
            }
            () @trusted { Thread.sleep(20.dur!"msecs"); }();
        }

        rval.output = output.data;
        return rval;
    }

    private auto startTests(Duration timeout, string[string] env) @trusted {
        auto tasks = appender!(TestTask*[])();

        foreach (c; commands) {
            auto t = task!spawnRunTest(c.cmd.value, timeout, env, earlyStopSignal);
            tasks.put(t);
            pool.put(t);
        }
        return tasks.data;
    }

    /// Find the test command and update its kill counter.
    private void incrCmdKills(string[] cmd) {
        foreach (ref a; commands) {
            if (a.cmd.value == cmd) {
                a.kills++;
                break;
            }
        }
    }
}

/// The result of running the tests.
struct TestResult {
    enum Status {
        /// All test commands exited with exit status zero.
        passed,
        /// At least one test command indicated that an error where found by exit status not zero.
        failed,
        /// At least one test command timed out.
        timeout,
        /// Something happend when the test command executed thus the result should not be used.
        error,
    }

    Status status;

    /// Output from all the test binaries and command.
    DrainElement[] output;
}

/// Finds all executables in a directory tree.
string[] findExecutables(AbsolutePath root) @trusted {
    import core.sys.posix.sys.stat;
    import std.file : getAttributes;
    import std.file : dirEntries, SpanMode;

    static bool isExecutable(string p) nothrow {
        try {
            return (getAttributes(p) & S_IXUSR) != 0;
        } catch (Exception e) {
        }
        return false;
    }

    auto app = appender!(string[])();
    foreach (f; dirEntries(root, SpanMode.breadth).filter!(a => a.isFile)
            .filter!(a => isExecutable(a.name))) {
        app.put([f.name]);
    }

    return app.data;
}

RunResult spawnRunTest(string[] cmd, Duration timeout, string[string] env, Signal earlyStop) @trusted nothrow {
    import std.algorithm : copy;
    static import std.process;

    RunResult rval;
    rval.cmd = cmd;

    if (earlyStop.isActive) {
        debug logger.tracef("Early stop detected. Skipping %s (%s)", cmd,
                Clock.currTime).collectException;
        return rval;
    }

    try {
        auto p = pipeProcess(cmd, std.process.Redirect.all, env).sandbox.timeout(timeout).scopeKill;
        auto output = appender!(DrainElement[])();
        foreach (a; p.process.drain(20.dur!"msecs")) {
            if (!a.empty)
                output.put(a);
            if (earlyStop.isActive) {
                debug logger.tracef("Early stop detected. Stopping %s (%s)", cmd, Clock.currTime);
                p.kill;
                break;
            }
        }

        if (p.timeoutTriggered) {
            rval.status = RunResult.Status.timeout;
        }

        rval.exitStatus = p.wait;
        rval.output = output.data;
    } catch (Exception e) {
        logger.warning(e.msg).collectException;
        rval.status = RunResult.Status.error;
    }

    if (rval.exitStatus != 0) {
        earlyStop.activate;
        debug logger.tracef("Early stop triggered by %s (%s)", rval.cmd,
                Clock.currTime).collectException;
    }

    return rval;
}

private:

struct RunResult {
    enum Status {
        /// the test command successfully executed.
        normal,
        /// Something happend when the test command executed thus the result should not be used.
        error,
        /// The test command timed out.
        timeout,
    }

    /// The command that where executed.
    string[] cmd;

    Status status;
    ///
    int exitStatus;
    ///
    DrainElement[] output;
}

string makeUnittestScript(string script, string file = __FILE__, uint line = __LINE__) {
    import core.sys.posix.sys.stat;
    import std.file : getAttributes, setAttributes, thisExePath;
    import std.stdio : File;
    import std.path : baseName;
    import std.conv : to;

    immutable fname = thisExePath ~ "_" ~ script ~ file.baseName ~ line.to!string ~ ".sh";

    File(fname, "w").writeln(`#!/bin/bash
echo $1
if [[ "$3" = "timeout" ]]; then
    sleep 10m
fi
exit $2`);
    setAttributes(fname, getAttributes(fname) | S_IXUSR | S_IXGRP | S_IXOTH);
    return fname;
}

version (unittest) {
    import core.time : dur;
    import std.algorithm : count;
    import std.array : array, empty;
    import std.file : remove, exists;
    import std.string : strip;
}

@("shall collect the result from the test commands when running them")
unittest {
    immutable script = makeUnittestScript("script_");
    scope (exit)
        () {
        if (exists(script))
            remove(script);
    }();

    auto runner = TestRunner.make(0);
    runner.put([script, "foo", "0"].ShellCommand);
    runner.put([script, "foo", "0"].ShellCommand);
    auto res = runner.run(5.dur!"seconds");

    res.output.filter!(a => !a.empty).count.shouldEqual(2);
    res.output.filter!(a => a.byUTF8.array.strip == "foo").count.shouldEqual(2);
    res.status.shouldEqual(TestResult.Status.passed);
}

@("shall set the status to failed when one of test command fail")
unittest {
    immutable script = makeUnittestScript("script_");
    scope (exit)
        () {
        if (exists(script))
            remove(script);
    }();

    auto runner = TestRunner.make(0);
    runner.put([script, "foo", "0"].ShellCommand);
    runner.put([script, "foo", "1"].ShellCommand);
    auto res = runner.run(5.dur!"seconds");

    res.output.filter!(a => !a.empty).count.shouldEqual(2);
    res.output.filter!(a => a.byUTF8.array.strip == "foo").count.shouldEqual(2);
    res.status.shouldEqual(TestResult.Status.failed);
}

@("shall set the status to timeout when one of the tests commands reach the timeout limit")
unittest {
    immutable script = makeUnittestScript("script_");
    scope (exit)
        () {
        if (exists(script))
            remove(script);
    }();

    auto runner = TestRunner.make(0);
    runner.put([script, "foo", "0"].ShellCommand);
    runner.put([script, "foo", "0", "timeout"].ShellCommand);
    auto res = runner.run(1.dur!"seconds");

    res.output.filter!(a => !a.empty).count.shouldEqual(1);
    res.output.filter!(a => a.byUTF8.array.strip == "foo").count.shouldEqual(1);
    res.status.shouldEqual(TestResult.Status.timeout);
}

/// Thread safe signal.
class Signal {
    import core.atomic : atomicLoad, atomicStore;

    shared int state;
    immutable bool isUsed;

    this(bool isUsed) @safe pure nothrow @nogc {
        this.isUsed = isUsed;
    }

    bool isActive() @safe nothrow @nogc const {
        if (!isUsed)
            return false;

        auto local = atomicLoad(state);
        return local != 0;
    }

    void activate() @safe nothrow @nogc {
        atomicStore(state, 1);
    }

    void reset() @safe nothrow @nogc {
        atomicStore(state, 0);
    }
}
