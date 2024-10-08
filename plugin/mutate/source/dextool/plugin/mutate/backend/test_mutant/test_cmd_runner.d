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

import core.sync.condition;
import core.sync.mutex;
import logger = std.experimental.logger;
import std.algorithm : filter, map, joiner;
import std.array : appender, Appender, empty, array;
import std.datetime : Duration, dur, Clock;
import std.exception : collectException;
import std.file : SpanMode;
import std.format : format;
import std.parallelism : TaskPool, Task, task;
import std.random : randomCover;
import std.range : take;
import std.typecons : Tuple;

import my.named_type;
import my.path : AbsolutePath, Path;
import my.set;
import proc;

import dextool.plugin.mutate.type : ShellCommand;
import dextool.plugin.mutate.backend.type : ExitStatus;

version (unittest) {
    import unit_threaded.assertions;
}

@safe:

struct TestRunner {
    alias MaxCaptureBytes = NamedType!(ulong, Tag!"MaxOutputCaptureBytes",
            ulong.init, TagStringable);
    alias MinAvailableMemBytes = NamedType!(ulong, Tag!"MinAvailableMemBytes",
            ulong.min, TagStringable);

    private {
        alias TestTask = Task!(spawnRunTest, ShellCommand, Duration, string[string],
                MaxCaptureBytes, MinAvailableMemBytes, Signal, Mutex, Condition);
        TaskPool pool;
        bool ownsPool;
        Duration timeout_;

        Signal earlyStopSignal;

        /// Commands that execute the test cases.
        alias TestCmd = Tuple!(ShellCommand, "cmd", double, "kills");
        TestCmd[] commands;
        long nrOfRuns;

        /// Environment to set when executing either binaries or the command.
        string[string] env;

        bool captureAllOutput;

        /// max bytes to save from a test case.
        MaxCaptureBytes maxOutput = 10 * 1024 * 1024;

        MinAvailableMemBytes minAvailableMem_;
    }

    static auto make(int poolSize) {
        return TestRunner(poolSize);
    }

    this(int poolSize_) {
        this.ownsPool = true;
        this.poolSize(poolSize_);
        this.earlyStopSignal = new Signal(false);
    }

    this(TaskPool pool, Duration timeout_, TestCmd[] commands, long nrOfRuns,
            bool captureAllOutput, MaxCaptureBytes maxOutput, MinAvailableMemBytes minAvailableMem_) {
        this.pool = pool;
        this.timeout_ = timeout_;
        this.earlyStopSignal = new Signal(false);
        this.commands = commands;
        this.nrOfRuns = nrOfRuns;
        this.captureAllOutput = captureAllOutput;
        this.maxOutput = maxOutput;
        this.minAvailableMem_ = minAvailableMem_;
    }

    ~this() {
        if (ownsPool)
            pool.stop;
    }

    TestRunner dup() {
        return TestRunner(pool, timeout_, commands, nrOfRuns, captureAllOutput,
                maxOutput, minAvailableMem_);
    }

    string[string] getDefaultEnv() @safe pure nothrow @nogc {
        return env;
    }

    void defaultEnv(string[string] env) @safe pure nothrow @nogc {
        this.env = env;
    }

    void maxOutputCapture(MaxCaptureBytes bytes) @safe pure nothrow @nogc {
        this.maxOutput = bytes;
    }

    void minAvailableMem(MinAvailableMemBytes bytes) @safe pure nothrow @nogc {
        this.minAvailableMem_ = bytes;
    }

    /** Stop executing tests as soon as one detects a failure.
     *
     * This lose some information about the test cases but mean that mutation
     * testing overall is executing faster.
     */
    void useEarlyStop(bool v) @safe nothrow {
        this.earlyStopSignal = new Signal(v);
    }

    void captureAll(bool v) @safe pure nothrow @nogc {
        this.captureAllOutput = v;
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
        if (!sh.value.empty)
            commands ~= TestCmd(sh, 0);
    }

    void put(ShellCommand[] shs) pure nothrow {
        foreach (a; shs)
            put(a);
    }

    TestCmd[] testCmds() @safe pure nothrow @nogc {
        return commands;
    }

    TestResult run() {
        return this.run(timeout_, null, SkipTests.init);
    }

    TestResult run(SkipTests skipTests) {
        return this.run(timeout_, null, skipTests);
    }

    TestResult run(string[string] localEnv) {
        return this.run(timeout_, localEnv, SkipTests.init);
    }

    TestResult run(Duration timeout, string[string] localEnv = null,
            SkipTests skipTests = SkipTests.init) {
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

        void processDone(TestTask* t, ref TestResult result) {
            auto res = t.yieldForce;

            result.exitStatus = mergeExitStatus(result.exitStatus, res.exitStatus);

            final switch (res.status) {
            case RunResult.Status.normal:
                if (result.status == TestResult.Status.passed && res.exitStatus.get != 0) {
                    result.status = TestResult.Status.failed;
                }
                if (res.exitStatus.get != 0) {
                    incrCmdKills(res.cmd);
                    result.output[res.cmd] = res.output;
                } else if (captureAllOutput && res.exitStatus.get == 0) {
                    result.output[res.cmd] = res.output;
                }
                break;
            case RunResult.Status.timeout:
                result.status = TestResult.Status.timeout;
                break;
            case RunResult.Status.memOverload:
                result.status = TestResult.Status.memOverload;
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

        auto mtx = new Mutex;
        auto condDone = new Condition(mtx);
        earlyStopSignal.reset;
        TestTask*[] tasks = startTests(timeout, env_, skipTests, mtx, condDone);
        TestResult rval;
        while (!tasks.empty) {
            auto t = findDone(tasks);
            if (t !is null) {
                processDone(t, rval);
                .destroy(t);
            } else {
                synchronized (mtx) {
                    () @trusted { condDone.wait(10.dur!"msecs"); }();
                }
            }
        }

        return rval;
    }

    private auto startTests(Duration timeout, string[string] env,
            SkipTests skipTests, Mutex mtx, Condition condDone) @trusted {
        auto tasks = appender!(TestTask*[])();

        foreach (c; commands.filter!(a => a.cmd.value[0]!in skipTests.get)) {
            auto t = task!spawnRunTest(c.cmd, timeout, env, maxOutput,
                    minAvailableMem_, earlyStopSignal, mtx, condDone);
            tasks.put(t);
            pool.put(t);
        }
        return tasks.data;
    }

    /// Find the test command and update its kill counter.
    private void incrCmdKills(ShellCommand cmd) {
        foreach (ref a; commands) {
            if (a.cmd == cmd) {
                a.kills++;
                break;
            }
        }
    }
}

alias SkipTests = NamedType!(Set!string, Tag!"SkipTests", Set!string.init, TagStringable);

/// The result of running the tests.
struct TestResult {
    enum Status {
        /// All test commands exited with exit status zero.
        passed,
        /// At least one test command indicated that an error where found by exit status not zero.
        failed,
        /// At least one test command timed out.
        timeout,
        /// memory overload
        memOverload,
        /// Something happend when the test command executed thus the result should not be used.
        error
    }

    Status status;
    ExitStatus exitStatus;

    /// Output from all test binaries and command with exist status != 0.
    DrainElement[][ShellCommand] output;
}

/// Finds all executables in a directory tree.
string[] findExecutables(AbsolutePath root, SpanMode mode = SpanMode.breadth) @trusted {
    import core.sys.posix.sys.stat;
    import std.file : getAttributes;
    import std.file : dirEntries;
    import my.file : isExecutable;

    auto app = appender!(string[])();
    foreach (f; dirEntries(root, mode).filter!(a => a.isFile)
            .filter!(a => isExecutable(Path(a.name)))) {
        app.put([f.name]);
    }

    return app.data;
}

RunResult spawnRunTest(ShellCommand cmd, Duration timeout, string[string] env, TestRunner.MaxCaptureBytes maxOutputCapture,
        TestRunner.MinAvailableMemBytes minAvailableMem, Signal earlyStop,
        Mutex mtx, Condition condDone) @trusted nothrow {
    import std.algorithm : copy;
    static import std.process;

    auto availMem = AvailableMem.make();
    scope (exit)
        () {
        try {
            .destroy(availMem);
        } catch (Exception e) {
        }
    }();
    bool isMemLimitTrigger() {
        return availMem.available < minAvailableMem.get;
    }

    scope (exit)
        () nothrow{
        try {
            synchronized (mtx) {
                condDone.notify;
            }
        } catch (Exception e) {
        }
    }();

    RunResult rval;
    rval.cmd = cmd;

    if (earlyStop.isActive) {
        debug logger.tracef("Early stop detected. Skipping %s (%s)", cmd,
                Clock.currTime).collectException;
        return rval;
    }

    try {
        auto p = pipeProcess(cmd.value, std.process.Redirect.all, env).sandbox.timeout(timeout);
        scope (exit)
            p.dispose;
        auto output = appender!(DrainElement[])();
        ulong outputBytes;
        foreach (a; p.process.drain) {
            if (!a.empty && (outputBytes + a.data.length) < maxOutputCapture.get) {
                output.put(a);
                outputBytes += a.data.length;
            }
            if (earlyStop.isActive) {
                debug logger.tracef("Early stop detected. Stopping %s (%s)", cmd, Clock.currTime);
                p.kill;
                break;
            }
            if (isMemLimitTrigger) {
                logger.infof("Available memory below limit. Stopping %s (%s < %s)",
                        cmd, availMem.available, minAvailableMem.get);
                p.kill;
                rval.status = RunResult.Status.memOverload;
                break;
            }
        }

        if (p.timeoutTriggered) {
            rval.status = RunResult.Status.timeout;
        }

        rval.exitStatus = p.wait.ExitStatus;
        rval.output = output.data;
    } catch (Exception e) {
        logger.warning(cmd).collectException;
        logger.warning(e.msg).collectException;
        rval.status = RunResult.Status.error;
    }

    if (rval.exitStatus.get != 0) {
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
        /// memory overload
        memOverload
    }

    /// The command that where executed.
    ShellCommand cmd;

    Status status;
    ///
    ExitStatus exitStatus;
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
    echo $2
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
    runner.captureAll(true);
    runner.put([script, "foo", "0"].ShellCommand);
    runner.put([script, "foo", "0"].ShellCommand);
    auto res = runner.run(5.dur!"seconds");

    res.output.byKey.count.shouldEqual(1);
    res.output.byValue.filter!"!a.empty".count.shouldEqual(1);
    res.output.byValue.joiner.filter!(a => a.byUTF8.array.strip == "foo").count.shouldEqual(1);
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

    res.output.byKey.count.shouldEqual(1);
    res.output.byValue.joiner.filter!(a => a.byUTF8.array.strip == "foo").count.shouldEqual(1);
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
    runner.put([script, "foo", "1", "timeout"].ShellCommand);
    auto res = runner.run(1.dur!"seconds");

    res.status.shouldEqual(TestResult.Status.timeout);
    res.output.byKey.count.shouldEqual(0); // no output should be saved
}

@("shall only capture at most default reduced to 4 bytes")
unittest {
    import std.algorithm : sum;

    immutable script = makeUnittestScript("script_");
    scope (exit)
        () {
        if (exists(script))
            remove(script);
    }();

    auto runner = TestRunner.make(0);
    runner.put([script, "my_output", "1"].ShellCommand);

    // capture up to default max.
    auto res = runner.run(1.dur!"seconds");
    res.output.byValue.joiner.map!(a => a.data.length).sum.shouldEqual(10);

    // reduce max and then nothing is captured because the minimum output is 9 byte
    runner.maxOutputCapture(TestRunner.MaxCaptureBytes(4));
    res = runner.run(1.dur!"seconds");
    res.output.byValue.joiner.map!(a => a.data.length).sum.shouldEqual(0);
}

/// Thread safe signal.
class Signal {
    import core.atomic : atomicLoad, atomicStore;

    shared int state;
    shared bool isUsed;

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

/// Merge the new exit code with the old one keeping the dominant.
ExitStatus mergeExitStatus(ExitStatus old, ExitStatus new_) {
    import std.algorithm : max, min;

    if (old.get == 0)
        return new_;

    if (old.get < 0) {
        return min(old.get, new_.get).ExitStatus;
    }

    // a value 128+n is a value from the OS which is pretty bad such as a segmentation fault.
    // those <128 are user created.
    return max(old.get, new_.get).ExitStatus;
}

struct AvailableMem {
    import std.conv : to;
    import std.datetime : SysTime;
    import std.stdio : File;
    import std.string : startsWith, split;

    static const Duration pollFreq = 5.dur!"seconds";
    File procMem;
    SysTime nextPoll;
    long current = long.max;

    static AvailableMem* make() @safe nothrow {
        try {
            return new AvailableMem(File("/proc/meminfo"), Clock.currTime);
        } catch (Exception e) {
            logger.warning("Unable to open /proc/meminfo").collectException;
        }
        return new AvailableMem(File.init, Clock.currTime);
    }

    long available() @trusted nothrow {
        if (Clock.currTime > nextPoll && procMem.isOpen) {
            try {
                procMem.rewind;
                procMem.flush;
                foreach (l; procMem.byLine
                        .filter!(l => l.startsWith("MemAvailable"))
                        .map!(a => a.split)
                        .filter!(a => a.length >= 3)) {
                    current = to!long(l[1]) * 1024;
                    break;
                }
            } catch (Exception e) {
                current = long.max;
            }
            nextPoll = Clock.currTime + pollFreq;
        }

        return current;
    }
}
