/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module process;

import core.sys.posix.unistd : pid_t;
import core.thread : Thread;
import core.time : dur, Duration;
import logger = std.experimental.logger;
import std.array : appender, empty;
import std.exception : collectException;
import std.stdio : File, fileno, writeln;
static import std.process;

import dextool.from;

public import process.channel;

version (unittest) {
    import unit_threaded.assertions;
}

/// RAII handling of a process instance.
auto raii(T)(T p) if (is(T : Process)) {
    return Raii!T(p);
}

struct Raii(T) {
    T process;
    alias process this;

    ~this() {
        process.destroy();
    }
}

///
interface Process {
    /// Access to stdin and stdout.
    Channel pipe() nothrow @safe;

    /// Access stderr.
    ReadChannel stderr() nothrow @safe;

    /// Kill and cleanup the process.
    void destroy() @safe;

    /// Kill the process.
    void kill() nothrow @safe;

    /// Blocking wait for the process to terminated.
    /// Returns: the exit status.
    int wait() @safe;

    /// Non-blocking wait for the process termination.
    /// Returns: `true` if the process has terminated.
    bool tryWait() nothrow @safe;

    /// Returns: The raw OS handle for the process ID.
    RawPid osHandle() nothrow @safe;

    /// Returns: The exit status of the process.
    int status() @safe;

    /// Returns: If the process has terminated.
    bool terminated() nothrow @safe;
}

/** Async process that do not block on read from stdin/stderr.
 */
class PipeProcess : Process {
    private {
        std.process.ProcessPipes process;
        Pipe pipe_;
        ReadChannel stderr_;
        int status_;
        bool terminated_;
    }

    this(std.process.ProcessPipes process) @safe {
        this.process = process;
        this.pipe_ = new Pipe(this.process.stdout, this.process.stdin);
        this.stderr_ = new FileReadChannel(this.process.stderr);
    }

    override RawPid osHandle() nothrow @safe {
        return process.pid.osHandle.RawPid;
    }

    override Channel pipe() nothrow @safe {
        return pipe_;
    }

    override ReadChannel stderr() nothrow @safe {
        return stderr_;
    }

    override void destroy() @safe {
        if (!terminated_) {
            this.kill;
            this.wait.collectException;
        }
        pipe_.destroy;
        stderr_.destroy;
    }

    override void kill() nothrow @trusted {
        import core.sys.posix.signal : SIGKILL;

        if (terminated_) {
            return;
        }

        try {
            std.process.kill(process.pid, SIGKILL);
        } catch (Exception e) {
        }

        terminated_ = true;
    }

    override int wait() @safe {
        if (!terminated_) {
            status_ = std.process.wait(process.pid);
            terminated_ = true;
        }
        return status_;
    }

    override bool tryWait() nothrow @safe {
        if (terminated_) {
            return true;
        }

        try {
            auto s = std.process.tryWait(process.pid);
            terminated_ = s.terminated;
            status_ = s.status;
            if (s.terminated) {
                terminated_ = true;
                status_ = s.status;
            }
        } catch (Exception e) {
            logger.trace(e.msg).collectException;
        }

        return terminated_;
    }

    override int status() @safe {
        if (!terminated_) {
            throw new Exception("Process has not terminated");
        }
        return status_;
    }

    override bool terminated() @safe {
        return terminated_;
    }
}

Process pipeProcess(scope const(char[])[] args,
        std.process.Redirect redirect = std.process.Redirect.all,
        const string[string] env = null, std.process.Config config = std.process.Config.none,
        scope const(char)[] workDir = null) @safe {
    return new PipeProcess(std.process.pipeProcess(args, redirect, env, config, workDir));
}

Process pipeShell(scope const(char)[] command,
        std.process.Redirect redirect = std.process.Redirect.all,
        const string[string] env = null, std.process.Config config = std.process.Config.none,
        scope const(char)[] workDir = null, string shellPath = std.process.nativeShell) @safe {
    return new PipeProcess(std.process.pipeShell(command, redirect, env,
            config, workDir, shellPath));
}

/** Moves the process to a separate process group and on exit kill it and all
 * its children.
 */
class Sandbox : Process {
    private {
        Process p;
    }

    this(Process p) @safe nothrow {
        import core.sys.posix.unistd;

        this.p = p;
        setpgid(p.osHandle, 0);
    }

    override RawPid osHandle() nothrow @safe {
        return p.osHandle;
    }

    override Channel pipe() nothrow @safe {
        return p.pipe;
    }

    override ReadChannel stderr() nothrow @safe {
        return p.stderr;
    }

    override void destroy() @safe {
        this.kill;
        p.destroy;
    }

    override void kill() nothrow @safe {
        import core.sys.posix.signal : kill, kill, SIGKILL;
        import core.sys.posix.sys.wait;
        import std.array : empty;

        RawPid[] update() @trusted {
            try {
                return getDeepChildren(p.osHandle);
            } catch (Exception e) {
            }
            return null;
        }

        static void killChildren(RawPid[] children) @trusted {
            foreach (const c; children) {
                core.sys.posix.signal.kill(c, SIGKILL);
                waitpid(c, null, WNOHANG);
            }
        }

        p.kill;
        auto children = update();
        // if there ever are processes that are spawned with root permissions
        // or something happens that they can't be killed by "this" process
        // tree. Thus limit the iterations to a reasonable number
        for (int i = 0; !children.empty && i < 5; ++i) {
            killChildren(children);
            children = update;
        }
    }

    override int wait() @safe {
        return p.wait;
    }

    override bool tryWait() nothrow @safe {
        return p.tryWait;
    }

    override int status() @safe {
        return p.status;
    }

    override bool terminated() @safe {
        return p.terminated;
    }
}

Process sandbox(Process p) @safe {
    return new Sandbox(p);
}

@("shall terminate a group of processes")
unittest {
    import core.sys.posix.sys.stat;
    import std.algorithm : count;
    import std.datetime.stopwatch : StopWatch, AutoStart;
    import std.file : setAttributes, getAttributes, remove;

    immutable scriptName = "./" ~ __FUNCTION__ ~ ".sh";
    File(scriptName, "w").writeln(`#!/bin/bash
sleep 10m &
sleep 10m &
sleep 10m
`);
    scope (exit)
        remove(scriptName);
    setAttributes(scriptName, getAttributes(scriptName) | S_IXUSR | S_IXGRP | S_IXOTH);

    auto p = pipeProcess([scriptName]).sandbox.raii;
    for (int i = 0; getDeepChildren(p.osHandle).count < 3; ++i) {
        Thread.sleep(50.dur!"msecs");
    }
    const preChildren = getDeepChildren(p.osHandle).count;
    p.kill;
    Thread.sleep(500.dur!"msecs"); // wait for the OS to kill the children
    const postChildren = getDeepChildren(p.osHandle).count;

    p.wait.shouldEqual(0);
    p.terminated.shouldBeTrue;
    preChildren.shouldEqual(3);
    postChildren.shouldEqual(0);
}

/** Terminate the process after the timeout. The timeout is checked in the
 * wait/tryWait methods.
 */
class Timeout : Process {
    import std.datetime : Clock, SysTime;

    private {
        Process p;
        SysTime stopAt;
        bool timeoutTriggered_;
    }

    this(Process p, Duration timeout) @safe nothrow {
        this.p = p;
        this.stopAt = Clock.currTime + timeout;
    }

    override RawPid osHandle() nothrow @safe {
        return p.osHandle;
    }

    override Channel pipe() nothrow @safe {
        return p.pipe;
    }

    override ReadChannel stderr() nothrow @safe {
        return p.stderr;
    }

    override void destroy() @safe {
        p.destroy;
    }

    override void kill() nothrow @safe {
        p.kill;
    }

    override int wait() @trusted {
        while (!this.tryWait) {
            Thread.sleep(20.dur!"msecs");
        }
        return p.wait;
    }

    override bool tryWait() nothrow @safe {
        if (!terminated && Clock.currTime > stopAt) {
            timeoutTriggered_ = true;
            p.kill;
        }
        return p.tryWait;
    }

    override int status() @safe {
        return p.status;
    }

    override bool terminated() @safe {
        return p.terminated;
    }

    bool timeoutTriggered() @safe pure nothrow const @nogc {
        return timeoutTriggered_;
    }
}

Timeout timeout(Process p, Duration timeout) @safe {
    return new Timeout(p, timeout);
}

@("shall kill the process after the timeout")
unittest {
    import std.datetime.stopwatch : StopWatch, AutoStart;

    auto p = pipeProcess(["sleep", "1m"]).timeout(100.dur!"msecs").raii;
    auto sw = StopWatch(AutoStart.yes);
    p.wait;
    sw.stop;

    sw.peek.shouldBeGreaterThan(100.dur!"msecs");
    p.tryWait.shouldBeTrue;
    p.status.shouldEqual(0);
}

/** Measure the runtime of a process.
 */
class MeasureTime : Process {
    import std.datetime.stopwatch : StopWatch;

    private {
        Process p;
        StopWatch sw;
    }

    this(Process p) @safe nothrow @nogc {
        this.p = p;
        sw.start;
    }

    override RawPid osHandle() nothrow @safe {
        return p.osHandle;
    }

    override Channel pipe() nothrow @safe {
        return p.pipe;
    }

    override ReadChannel stderr() nothrow @safe {
        return p.stderr;
    }

    override void destroy() @safe {
        p.destroy;
    }

    override void kill() nothrow @safe {
        p.kill;
    }

    override int wait() @safe {
        if (!terminated) {
            p.wait;
            sw.stop;
        }
        return p.status;
    }

    override bool tryWait() nothrow @safe {
        if (!terminated && p.tryWait) {
            sw.stop;
        }
        return p.terminated;
    }

    override int status() @safe {
        return p.status;
    }

    override bool terminated() @safe {
        return p.terminated;
    }

    Duration time() @safe nothrow const @nogc {
        return sw.peek;
    }
}

MeasureTime measureTime(Process p) @safe nothrow {
    return new MeasureTime(p);
}

struct RawPid {
    pid_t value;
    alias value this;
}

RawPid[] getShallowChildren(const int parentPid) {
    import std.algorithm : filter, splitter;
    import std.conv : to;
    import std.file : exists;
    import std.path : buildPath;

    const pidPath = buildPath("/proc", parentPid.to!string);
    if (!exists(pidPath)) {
        return null;
    }

    auto children = appender!(RawPid[])();
    foreach (const p; File(buildPath(pidPath, "task", parentPid.to!string, "children")).readln.splitter(" ")
            .filter!(a => !a.empty)) {
        try {
            children.put(p.to!pid_t.RawPid);
        } catch (Exception e) {
            logger.trace(e.msg).collectException;
        }
    }

    return children.data;
}

/// Returns: a list of all processes with the leafs being at the back.
RawPid[] getDeepChildren(const int parentPid) {
    import std.container : DList;

    auto children = DList!(RawPid)();

    children.insert(getShallowChildren(parentPid));
    auto res = appender!(RawPid[])();

    while (!children.empty) {
        const p = children.front;
        res.put(p);
        children.insertBack(getShallowChildren(p));
        children.removeFront;
    }

    return res.data;
}

/// Returns when the process has pending data.
void waitForPendingData(Process p) {
    while (!p.pipe.hasPendingData || p.stderr.hasPendingData) {
        Thread.sleep(20.dur!"msecs");
    }
}

struct DrainElement {
    enum Type {
        stdout,
        stderr,
    }

    Type type;
    const(ubyte)[] data;

    /// Returns: iterates the data as an input range.
    auto byUTF8() @safe pure nothrow const @nogc {
        import std.algorithm : map;
        static import std.utf;

        return std.utf.byUTF!(const(char))(data.map!(a => cast(const(char)) a));
    }
}

/** A range that drains a process stdout/stderr until it terminates.
 *
 * There may be `DrainElement` that are empty.
 */
struct DrainRange {
    enum State {
        start,
        draining,
        lastStdout,
        lastStderr,
        lastElement,
        empty,
    }

    private {
        Process p;
        DrainElement front_;
        State st;
    }

    DrainElement front() @safe pure nothrow const @nogc {
        assert(!empty, "Can't get front of an empty range");
        return front_;
    }

    void popFront() @safe {
        assert(!empty, "Can't pop front of an empty range");

        bool isAnyPipeOpen() {
            return p.pipe.hasData || p.stderr.hasData;
        }

        void readData() @safe {
            if (p.pipe.hasData && p.pipe.hasPendingData) {
                front_ = DrainElement(DrainElement.Type.stdout, p.pipe.read(4096));
            } else if (p.stderr.hasData && p.stderr.hasPendingData) {
                front_ = DrainElement(DrainElement.Type.stderr, p.stderr.read(4096));
            }
        }

        void waitUntilData() @safe {
            while (front_.data.empty && isAnyPipeOpen) {
                import core.thread : Thread;
                import core.time : dur;

                readData();
                if (front_.data.empty) {
                    () @trusted { Thread.sleep(20.dur!"msecs"); }();
                }
            }
        }

        front_ = DrainElement.init;

        final switch (st) {
        case State.start:
            st = State.draining;
            waitUntilData;
            break;
        case State.draining:
            if (isAnyPipeOpen) {
                waitUntilData();
            } else {
                st = State.lastStdout;
            }
            break;
        case State.lastStdout:
            st = State.lastStderr;
            readData();
            if (p.pipe.hasData && p.pipe.hasPendingData) {
                st = State.lastStdout;
            }
            break;
        case State.lastStderr:
            st = State.lastElement;
            readData();
            if (p.stderr.hasData && p.stderr.hasPendingData) {
                st = State.lastStderr;
            }
            break;
        case State.lastElement:
            st = State.empty;
            break;
        case State.empty:
            break;
        }
    }

    bool empty() @safe pure nothrow const @nogc {
        return st == State.empty;
    }
}

/// Drain a process pipe until empty.
DrainRange drain(Process p) @safe pure nothrow @nogc {
    return DrainRange(p);
}

/// Drain the process output until it is done executing.
Process drainToNull(Process p) @safe {
    foreach (l; p.drain) {
    }
    return p;
}

/// Drain the output from the process into an output range.
Process drain(T)(Process p, ref T range) {
    foreach (l; p.drain) {
        range.put(l);
    }
    return p;
}

@("shall drain the output of a process while it is running with a separation of stdout and stderr")
unittest {
    import std.algorithm : filter, count, joiner, map;
    import std.array : array;

    auto p = pipeProcess(["dd", "if=/dev/urandom", "bs=10", "count=3"]).raii;
    auto res = p.drain.array;

    writeln(res);

    // this is just a sanity check. It has to be kind a high because there is
    // some wiggleroom allowed
    res.count.shouldBeSmallerThan(50);

    res.filter!(a => a.type == DrainElement.Type.stdout)
        .map!(a => a.data)
        .joiner
        .count
        .shouldEqual(30);
    res.filter!(a => a.type == DrainElement.Type.stderr).count.shouldEqual(1);
    p.wait.shouldEqual(0);
    p.terminated.shouldBeTrue;
}
