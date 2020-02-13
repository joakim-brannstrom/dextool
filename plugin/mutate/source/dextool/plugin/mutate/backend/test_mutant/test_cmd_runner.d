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
import std.algorithm : filter;
import std.array : appender, Appender, empty;
import std.datetime : Duration, dur;
import std.exception : collectException;
import std.parallelism : TaskPool, Task, task;

import process;

import dextool.plugin.mutate.type : ShellCommand;
import dextool.type;

version (unittest) {
    import unit_threaded.assertions;
}

@safe:

struct TestRunner {
    private {
        alias TestTask = Task!(spawnRunTest, string[], Duration, string[string]);
        TaskPool pool;
        Duration timeout_;
    }

    /// Commands that execute the test cases.
    ShellCommand[] commands;

    /// Environment to set when executing either binaries or the command.
    string[string] env;

    static auto make(int poolSize) {
        auto pool = () {
            if (poolSize == 0) {
                return new TaskPool;
            }
            return new TaskPool(poolSize);
        }();
        pool.isDaemon = true;
        return TestRunner(pool);
    }

    ~this() {
        pool.stop;
    }

    bool empty() @safe pure nothrow const @nogc {
        return commands.length == 0;
    }

    void timeout(Duration timeout) pure nothrow @nogc {
        this.timeout_ = timeout;
    }

    void put(ShellCommand sh) pure nothrow {
        commands ~= sh;
    }

    void put(ShellCommand[] sh) pure nothrow {
        commands ~= sh;
    }

    TestResult run(string[string] localEnv = null) {
        return this.run(timeout_, localEnv);
    }

    TestResult run(Duration timeout, string[string] localEnv = null) {
        import core.thread : Thread;
        import core.time : dur;
        import std.range : enumerate;

        static TestTask* findDone(ref TestTask*[] tasks) {
            foreach (t; tasks.enumerate.filter!(a => a.value.done)) {
                tasks[t.index] = tasks[$ - 1];
                tasks = tasks[0 .. $ - 1];
                return t.value;
            }
            return null;
        }

        static void processDone(TestTask* t, ref TestResult result,
                ref Appender!(DrainElement[]) output) {
            auto res = t.yieldForce;
            final switch (res.status) {
            case RunResult.Status.normal:
                if (result.status == TestResult.Status.passed && res.exitStatus != 0) {
                    result.status = TestResult.Status.failed;
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

        TestTask*[] tasks = startTests(timeout, env_);
        TestResult rval;
        auto output = appender!(DrainElement[])();
        while (!tasks.empty) {
            auto t = findDone(tasks);
            if (t !is null) {
                processDone(t, rval, output);
            }
            () @trusted { Thread.sleep(50.dur!"msecs"); }();
        }

        rval.output = output.data;
        return rval;
    }

    private auto startTests(Duration timeout, string[string] env) @trusted {
        auto tasks = appender!(TestTask*[])();

        foreach (c; commands) {
            auto t = task!spawnRunTest(c.value, timeout, env);
            tasks.put(t);
            pool.put(t);
        }
        return tasks.data;
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

RunResult spawnRunTest(string[] cmd, Duration timeout, string[string] env) @trusted nothrow {
    import std.algorithm : copy;
    static import std.process;

    RunResult rval;

    try {
        auto p = pipeProcess(cmd, std.process.Redirect.all, env).sandbox.timeout(timeout).scopeKill;
        auto output = appender!(DrainElement[])();
        p.process.drain(200.dur!"msecs").copy(output);

        if (p.timeoutTriggered) {
            rval.status = RunResult.Status.timeout;
        }

        rval.exitStatus = p.wait;
        rval.output = output.data;
    } catch (Exception e) {
        logger.warning(e.msg).collectException;
        rval.status = RunResult.Status.error;
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
