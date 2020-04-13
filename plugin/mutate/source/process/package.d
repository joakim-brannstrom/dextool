/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module process;

import core.thread : Thread;
import core.time : dur, Duration;
import logger = std.experimental.logger;
import std.algorithm : filter, count, joiner, map;
import std.array : appender, empty, array;
import std.exception : collectException;
import std.stdio : File, fileno, writeln;
static import std.process;
static import std.stdio;

public import process.channel;
public import process.pid;

version (unittest) {
    import unit_threaded.assertions;
    import std.file : remove;
}

/// Automatically terminate the process when it goes out of scope.
auto scopeKill(T)(T p) {
    return ScopeKill!T(p);
}

struct ScopeKill(T) {
    T process;
    alias process this;

    ~this() {
        process.dispose();
    }
}

/// Async process wrapper for a std.process SpawnProcess
struct SpawnProcess {
    import std.algorithm : among;

    private {
        enum State {
            running,
            terminated,
            exitCode
        }

        std.process.Pid process;
        RawPid pid;
        int status_;
        State st;
    }

    this(std.process.Pid process) @safe {
        this.process = process;
        this.pid = process.osHandle.RawPid;
    }

    /// Returns: The raw OS handle for the process ID.
    RawPid osHandle() nothrow @safe {
        return pid;
    }

    /// Kill and cleanup the process.
    void dispose() @safe {
        final switch (st) {
        case State.running:
            this.kill;
            this.wait;
            break;
        case State.terminated:
            this.wait;
            break;
        case State.exitCode:
            break;
        }

        st = State.exitCode;
    }

    /// Kill the process.
    void kill() nothrow @trusted {
        import core.sys.posix.signal : SIGKILL;

        final switch (st) {
        case State.running:
            break;
        case State.terminated:
            goto case;
        case State.exitCode:
            return;
        }

        try {
            std.process.kill(process, SIGKILL);
        } catch (Exception e) {
        }

        st = State.terminated;
    }

    /// Blocking wait for the process to terminated.
    /// Returns: the exit status.
    int wait() @safe {
        final switch (st) {
        case State.running:
            status_ = std.process.wait(process);
            break;
        case State.terminated:
            status_ = std.process.wait(process);
            break;
        case State.exitCode:
            break;
        }

        st = State.exitCode;

        return status_;
    }

    /// Non-blocking wait for the process termination.
    /// Returns: `true` if the process has terminated.
    bool tryWait() @safe {
        final switch (st) {
        case State.running:
            auto s = std.process.tryWait(process);
            if (s.terminated) {
                st = State.exitCode;
                status_ = s.status;
            }
            break;
        case State.terminated:
            status_ = std.process.wait(process);
            st = State.exitCode;
            break;
        case State.exitCode:
            break;
        }

        return st.among(State.terminated, State.exitCode) != 0;
    }

    /// Returns: The exit status of the process.
    int status() @safe {
        if (st != State.exitCode) {
            throw new Exception(
                    "Process has not terminated and wait/tryWait been called to collect the exit status");
        }
        return status_;
    }

    /// Returns: If the process has terminated.
    bool terminated() @safe {
        return st.among(State.terminated, State.exitCode) != 0;
    }
}

/// Async process that do not block on read from stdin/stderr.
struct PipeProcess {
    import std.algorithm : among;

    private {
        enum State {
            running,
            terminated,
            exitCode
        }

        std.process.ProcessPipes process;
        Pipe pipe_;
        FileReadChannel stderr_;
        int status_;
        State st;
        RawPid pid;
    }

    this(std.process.ProcessPipes process) @safe {
        this.process = process;
        this.pipe_ = Pipe(this.process.stdout, this.process.stdin);
        this.stderr_ = FileReadChannel(this.process.stderr);
        this.pid = process.pid.osHandle.RawPid;
    }

    /// Returns: The raw OS handle for the process ID.
    RawPid osHandle() nothrow @safe {
        return this.pid;
    }

    /// Access to stdin and stdout.
    ref Pipe pipe() return scope nothrow @safe {
        return pipe_;
    }

    /// Access stderr.
    ref FileReadChannel stderr() return scope nothrow @safe {
        return stderr_;
    }

    /// Kill and cleanup the process.
    void dispose() @safe {
        final switch (st) {
        case State.running:
            this.kill;
            this.wait;
            .destroy(process);
            break;
        case State.terminated:
            this.wait;
            .destroy(process);
            break;
        case State.exitCode:
            break;
        }

        st = State.exitCode;
    }

    /// Kill the process.
    void kill() nothrow @trusted {
        import core.sys.posix.signal : SIGKILL;

        final switch (st) {
        case State.running:
            break;
        case State.terminated:
            return;
        case State.exitCode:
            return;
        }

        try {
            std.process.kill(process.pid, SIGKILL);
        } catch (Exception e) {
        }

        st = State.terminated;
    }

    /// Blocking wait for the process to terminated.
    /// Returns: the exit status.
    int wait() @safe {
        final switch (st) {
        case State.running:
            status_ = std.process.wait(process.pid);
            break;
        case State.terminated:
            status_ = std.process.wait(process.pid);
            break;
        case State.exitCode:
            break;
        }

        st = State.exitCode;

        return status_;
    }

    /// Non-blocking wait for the process termination.
    /// Returns: `true` if the process has terminated.
    bool tryWait() @safe {
        final switch (st) {
        case State.running:
            auto s = std.process.tryWait(process.pid);
            if (s.terminated) {
                st = State.exitCode;
                status_ = s.status;
            }
            break;
        case State.terminated:
            status_ = std.process.wait(process.pid);
            st = State.exitCode;
            break;
        case State.exitCode:
            break;
        }

        return st.among(State.terminated, State.exitCode) != 0;
    }

    /// Returns: The exit status of the process.
    int status() @safe {
        if (st != State.exitCode) {
            throw new Exception(
                    "Process has not terminated and wait/tryWait been called to collect the exit status");
        }
        return status_;
    }

    /// Returns: If the process has terminated.
    bool terminated() @safe {
        return st.among(State.terminated, State.exitCode) != 0;
    }
}

SpawnProcess spawnProcess(scope const(char[])[] args, File stdin = std.stdio.stdin,
        File stdout = std.stdio.stdout, File stderr = std.stdio.stderr,
        const string[string] env = null, std.process.Config config = std.process.Config.none,
        scope const char[] workDir = null) {
    return SpawnProcess(std.process.spawnProcess(args, stdin, stdout, stderr,
            env, config, workDir));
}

SpawnProcess spawnProcess(scope const(char[])[] args, const string[string] env,
        std.process.Config config = std.process.Config.none, scope const(char)[] workDir = null) {
    return SpawnProcess(std.process.spawnProcess(args, std.stdio.stdin,
            std.stdio.stdout, std.stdio.stderr, env, config, workDir));
}

SpawnProcess spawnProcess(scope const(char)[] program,
        File stdin = std.stdio.stdin, File stdout = std.stdio.stdout,
        File stderr = std.stdio.stderr, const string[string] env = null,
        std.process.Config config = std.process.Config.none, scope const(char)[] workDir = null) {
    return SpawnProcess(std.process.spawnProcess((&program)[0 .. 1], stdin,
            stdout, stderr, env, config, workDir));
}

SpawnProcess spawnShell(scope const(char)[] command, File stdin = std.stdio.stdin,
        File stdout = std.stdio.stdout, File stderr = std.stdio.stderr,
        scope const string[string] env = null, std.process.Config config = std.process.Config.none,
        scope const(char)[] workDir = null, scope string shellPath = std.process.nativeShell) {
    return SpawnProcess(std.process.spawnShell(command, stdin, stdout, stderr,
            env, config, workDir, shellPath));
}

/// ditto
SpawnProcess spawnShell(scope const(char)[] command, scope const string[string] env,
        std.process.Config config = std.process.Config.none,
        scope const(char)[] workDir = null, scope string shellPath = std.process.nativeShell) {
    return SpawnProcess(std.process.spawnShell(command, env, config, workDir, shellPath));
}

PipeProcess pipeProcess(scope const(char[])[] args,
        std.process.Redirect redirect = std.process.Redirect.all,
        const string[string] env = null, std.process.Config config = std.process.Config.none,
        scope const(char)[] workDir = null) @safe {
    return PipeProcess(std.process.pipeProcess(args, redirect, env, config, workDir));
}

PipeProcess pipeShell(scope const(char)[] command,
        std.process.Redirect redirect = std.process.Redirect.all,
        const string[string] env = null, std.process.Config config = std.process.Config.none,
        scope const(char)[] workDir = null, string shellPath = std.process.nativeShell) @safe {
    return PipeProcess(std.process.pipeShell(command, redirect, env, config, workDir, shellPath));
}

/** Moves the process to a separate process group and on exit kill it and all
 * its children.
 */
struct Sandbox(ProcessT) {
    private {
        ProcessT p;
        RawPid pid;
    }

    this(ProcessT p) @safe {
        import core.sys.posix.unistd : setpgid;

        this.p = p;
        this.pid = p.osHandle;
        setpgid(pid, 0);
    }

    RawPid osHandle() nothrow @safe {
        return pid;
    }

    static if (__traits(hasMember, ProcessT, "pipe")) {
        ref Pipe pipe() nothrow @safe {
            return p.pipe;
        }
    }

    static if (__traits(hasMember, ProcessT, "stderr")) {
        ref FileReadChannel stderr() nothrow @safe {
            return p.stderr;
        }
    }

    void dispose() @safe {
        // this also reaps the children thus cleaning up zombies
        this.kill;
        p.dispose;
    }

    void kill() nothrow @safe {
        import process.pid;

        // must first retrieve the submap because after the process is killed
        // its children may have changed.
        auto pmap = makePidMap.getSubMap(pid);

        p.kill;

        // only kill and reap the children
        pmap.remove(pid);
        process.pid.kill(pmap).reap;
    }

    int wait() @safe {
        return p.wait;
    }

    bool tryWait() @safe {
        return p.tryWait;
    }

    int status() @safe {
        return p.status;
    }

    bool terminated() @safe {
        return p.terminated;
    }
}

auto sandbox(T)(T p) @safe {
    return Sandbox!T(p);
}

@("shall terminate a group of processes")
unittest {
    import std.datetime.stopwatch : StopWatch, AutoStart;

    immutable scriptName = makeScript(`#!/bin/bash
sleep 10m &
sleep 10m &
sleep 10m
`);
    scope (exit)
        remove(scriptName);

    auto p = pipeProcess([scriptName]).sandbox.scopeKill;
    waitUntilChildren(p.osHandle, 3);
    const preChildren = makePidMap.getSubMap(p.osHandle).remove(p.osHandle).length;
    p.kill;
    Thread.sleep(500.dur!"msecs"); // wait for the OS to kill the children
    const postChildren = makePidMap.getSubMap(p.osHandle).remove(p.osHandle).length;

    p.wait.shouldEqual(-9);
    p.terminated.shouldBeTrue;
    preChildren.shouldEqual(3);
    postChildren.shouldEqual(0);
}

/** dispose the process after the timeout.
 */
struct Timeout(ProcessT) {
    import std.algorithm : among;
    import std.datetime : Clock, Duration;
    import core.thread;
    import std.typecons : RefCounted, refCounted;

    private {
        enum Msg {
            none,
            stop,
            status,
        }

        enum Reply {
            none,
            running,
            normalDeath,
            killedByTimeout,
        }

        static struct Payload {
            ProcessT p;
            RawPid pid;
            Background background;
            Reply backgroundReply;
        }

        RefCounted!Payload rc;
    }

    this(ProcessT p, Duration timeout) @trusted {
        import std.algorithm : move;

        auto pid = p.osHandle;
        rc = refCounted(Payload(move(p), pid));
        rc.background = new Background(&rc.p, timeout);
        rc.background.isDaemon = true;
        rc.background.start;
    }

    private static class Background : Thread {
        import core.sync.condition : Condition;
        import core.sync.mutex : Mutex;

        Duration timeout;
        ProcessT* p;
        Mutex mtx;
        Msg[] msg;
        Reply reply_;
        RawPid pid;

        this(ProcessT* p, Duration timeout) {
            this.p = p;
            this.timeout = timeout;
            this.mtx = new Mutex();
            this.pid = p.osHandle;

            super(&run);
        }

        void run() {
            checkProcess(this.pid, this.timeout, this);
        }

        void put(Msg msg) @trusted nothrow {
            this.mtx.lock_nothrow();
            scope (exit)
                this.mtx.unlock_nothrow();
            this.msg ~= msg;
        }

        Msg popMsg() @trusted nothrow {
            this.mtx.lock_nothrow();
            scope (exit)
                this.mtx.unlock_nothrow();
            if (msg.empty)
                return Msg.none;
            auto rval = msg[$ - 1];
            msg = msg[0 .. $ - 1];
            return rval;
        }

        void setReply(Reply reply_) @trusted nothrow {
            this.mtx.lock_nothrow();
            scope (exit)
                this.mtx.unlock_nothrow();
            this.reply_ = reply_;
        }

        Reply reply() @trusted nothrow {
            this.mtx.lock_nothrow();
            scope (exit)
                this.mtx.unlock_nothrow();
            return reply_;
        }

        void kill() @trusted nothrow {
            this.mtx.lock_nothrow();
            scope (exit)
                this.mtx.unlock_nothrow();
            p.kill;
        }
    }

    private static void checkProcess(RawPid p, Duration timeout, Background bg) nothrow {
        import core.sys.posix.signal : SIGKILL;
        import std.algorithm : max, min;
        import std.variant : Variant;
        static import core.sys.posix.signal;

        const stopAt = Clock.currTime + timeout;
        // the purpose is to poll the process often "enough" that if it
        // terminates early `Process` detects it fast enough. 1000 is chosen
        // because it "feels good". the purpose
        auto sleepInterval = min(500, max(20, timeout.total!"msecs" / 1000)).dur!"msecs";

        bool forceStop;
        bool running = true;
        while (running && Clock.currTime < stopAt) {
            const msg = bg.popMsg;

            final switch (msg) {
            case Msg.none:
                Thread.sleep(sleepInterval);
                break;
            case Msg.stop:
                forceStop = true;
                running = false;
                break;
            case Msg.status:
                bg.setReply(Reply.running);
                break;
            }

            if (core.sys.posix.signal.kill(p, 0) == -1) {
                running = false;
            }
        }

        // may be children alive thus must ensure that the whole process tree
        // is killed if this is a sandbox with a timeout.
        bg.kill;

        if (!forceStop && Clock.currTime >= stopAt) {
            bg.setReply(Reply.killedByTimeout);
        } else {
            bg.setReply(Reply.normalDeath);
        }
    }

    RawPid osHandle() nothrow @trusted {
        return rc.pid;
    }

    ref Pipe pipe() nothrow @trusted {
        return rc.p.pipe;
    }

    ref FileReadChannel stderr() nothrow @trusted {
        return rc.p.stderr;
    }

    void dispose() @trusted {
        if (rc.backgroundReply.among(Reply.none, Reply.running)) {
            rc.background.put(Msg.stop);
            rc.background.join;
            rc.backgroundReply = rc.background.reply;
        }
        rc.p.dispose;
    }

    void kill() nothrow @trusted {
        rc.background.kill;
    }

    int wait() @trusted {
        while (!this.tryWait) {
            Thread.sleep(20.dur!"msecs");
        }
        return rc.p.wait;
    }

    bool tryWait() @trusted {
        return rc.p.tryWait;
    }

    int status() @trusted {
        return rc.p.status;
    }

    bool terminated() @trusted {
        return rc.p.terminated;
    }

    bool timeoutTriggered() @trusted {
        if (rc.backgroundReply.among(Reply.none, Reply.running)) {
            rc.background.put(Msg.status);
            rc.backgroundReply = rc.background.reply;
        }
        return rc.backgroundReply == Reply.killedByTimeout;
    }
}

auto timeout(T)(T p, Duration timeout_) @trusted {
    return Timeout!T(p, timeout_);
}

/// Returns when the process has pending data.
void waitForPendingData(ProcessT)(Process p) {
    while (!p.pipe.hasPendingData || !p.stderr.hasPendingData) {
        Thread.sleep(20.dur!"msecs");
    }
}

@("shall kill the process after the timeout")
unittest {
    import std.datetime.stopwatch : StopWatch, AutoStart;

    auto p = pipeProcess(["sleep", "1m"]).timeout(100.dur!"msecs").scopeKill;
    auto sw = StopWatch(AutoStart.yes);
    p.wait;
    sw.stop;

    sw.peek.shouldBeGreaterThan(100.dur!"msecs");
    sw.peek.shouldBeSmallerThan(500.dur!"msecs");
    p.wait.shouldEqual(-9);
    p.terminated.shouldBeTrue;
    p.status.shouldEqual(-9);
    p.timeoutTriggered.shouldBeTrue;
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
        static import std.utf;

        return std.utf.byUTF!(const(char))(cast(const(char)[]) data);
    }

    bool empty() @safe pure nothrow const @nogc {
        return data.length == 0;
    }
}

/** A range that drains a process stdout/stderr until it terminates.
 *
 * There may be `DrainElement` that are empty.
 */
struct DrainRange(ProcessT) {
    enum State {
        start,
        draining,
        lastStdout,
        lastStderr,
        lastElement,
        empty,
    }

    private {
        Duration timeout;
        ProcessT p;
        DrainElement front_;
        State st;
        ubyte[] buf;
        ubyte[] bufRead;
    }

    this(ProcessT p, Duration timeout) {
        this.p = p;
        this.buf = new ubyte[4096];
        this.timeout = timeout;
    }

    DrainElement front() @safe pure nothrow const @nogc {
        assert(!empty, "Can't get front of an empty range");
        return front_;
    }

    void popFront() @safe {
        assert(!empty, "Can't pop front of an empty range");

        bool isAnyPipeOpen() {
            return (p.pipe.hasData || p.stderr.hasData) && !p.terminated;
        }

        void readData() @safe {
            if (p.stderr.hasData && p.stderr.hasPendingData) {
                front_ = DrainElement(DrainElement.Type.stderr);
                bufRead = p.stderr.read(buf);
            } else if (p.pipe.hasData && p.pipe.hasPendingData) {
                front_ = DrainElement(DrainElement.Type.stdout);
                bufRead = p.pipe.read(buf);
            }
        }

        void waitUntilData() @safe {
            // may livelock if the process never terminates and never writes to
            // the terminal. waitTime ensure that it sooner or later is
            // interrupted. It lets e.g the timeout handling to kill the
            // process.
            const s = 20.dur!"msecs";
            Duration waitTime;
            while (waitTime < timeout) {
                import core.thread : Thread;
                import core.time : dur;

                readData();
                if (front_.data.empty) {
                    () @trusted { Thread.sleep(s); }();
                    waitTime += s;
                }

                if (!(bufRead.empty && isAnyPipeOpen)) {
                    front_.data = bufRead.dup;
                    break;
                }
            }
        }

        front_ = DrainElement.init;
        bufRead = null;

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
            if (p.pipe.hasData && p.pipe.hasPendingData) {
                front_ = DrainElement(DrainElement.Type.stdout);
                bufRead = p.pipe.read(buf);
            }

            front_.data = bufRead.dup;
            if (!p.pipe.hasData || p.terminated) {
                st = State.lastStderr;
            }
            break;
        case State.lastStderr:
            if (p.stderr.hasData && p.stderr.hasPendingData) {
                front_ = DrainElement(DrainElement.Type.stderr);
                bufRead = p.stderr.read(buf);
            }

            front_.data = bufRead.dup;
            if (!p.stderr.hasData || p.terminated) {
                st = State.lastElement;
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
auto drain(T)(T p, Duration timeout) {
    return DrainRange!T(p, timeout);
}

/// Read the data from a ReadChannel by line.
struct DrainByLineCopyRange(ProcessT) {
    private {
        ProcessT process;
        DrainRange!ProcessT range;
        const(ubyte)[] buf;
        const(char)[] line;
    }

    this(ProcessT p, Duration timeout) @safe {
        process = p;
        range = p.drain(timeout);
    }

    string front() @trusted pure nothrow const @nogc {
        import std.exception : assumeUnique;

        assert(!empty, "Can't get front of an empty range");
        return line.assumeUnique;
    }

    void popFront() @safe {
        assert(!empty, "Can't pop front of an empty range");
        import std.algorithm : countUntil;
        import std.array : array;
        static import std.utf;

        void fillBuf() {
            if (!range.empty) {
                range.popFront;
            }
            if (!range.empty) {
                buf ~= range.front.data;
            }
        }

        size_t idx;
        do {
            fillBuf();
            idx = buf.countUntil('\n');
        }
        while (!range.empty && idx == -1);

        const(ubyte)[] tmp;
        if (buf.empty) {
            // do nothing
        } else if (idx == -1) {
            tmp = buf;
            buf = null;
        } else {
            idx = () {
                if (idx < buf.length) {
                    return idx + 1;
                }
                return idx;
            }();
            tmp = buf[0 .. idx];
            buf = buf[idx .. $];
        }

        if (!tmp.empty && tmp[$ - 1] == '\n') {
            tmp = tmp[0 .. $ - 1];
        }

        line = std.utf.byUTF!(const(char))(cast(const(char)[]) tmp).array;
    }

    bool empty() @safe pure nothrow const @nogc {
        return range.empty && buf.empty && line.empty;
    }
}

@("shall drain the process output by line")
unittest {
    import std.algorithm : filter, joiner, map;
    import std.array : array;

    auto p = pipeProcess(["dd", "if=/dev/zero", "bs=10", "count=3"]).scopeKill;
    auto res = p.process.drainByLineCopy(1.dur!"minutes").filter!"!a.empty".array;

    res.length.shouldEqual(4);
    res.joiner.count.shouldBeGreaterThan(30);
    p.wait.shouldEqual(0);
    p.terminated.shouldBeTrue;
}

auto drainByLineCopy(T)(T p, Duration timeout) @safe {
    return DrainByLineCopyRange!T(p, timeout);
}

/// Drain the process output until it is done executing.
auto drainToNull(T)(T p, Duration timeout) @safe {
    foreach (l; p.drain(timeout)) {
    }
    return p;
}

/// Drain the output from the process into an output range.
auto drain(ProcessT, T)(ProcessT p, ref T range, Duration timeout) {
    foreach (l; p.drain(timeout)) {
        range.put(l);
    }
    return p;
}

@("shall drain the output of a process while it is running with a separation of stdout and stderr")
unittest {
    auto p = pipeProcess(["dd", "if=/dev/urandom", "bs=10", "count=3"]).scopeKill;
    auto res = p.process.drain(1.dur!"minutes").array;

    // this is just a sanity check. It has to be kind a high because there is
    // some wiggleroom allowed
    res.count.shouldBeSmallerThan(50);

    res.filter!(a => a.type == DrainElement.Type.stdout)
        .map!(a => a.data)
        .joiner
        .count
        .shouldEqual(30);
    res.filter!(a => a.type == DrainElement.Type.stderr).count.shouldBeGreaterThan(0);
    p.wait.shouldEqual(0);
    p.terminated.shouldBeTrue;
}

@("shall kill the process tree when the timeout is reached")
unittest {
    immutable script = makeScript(`#!/bin/bash
sleep 10m
`);
    scope (exit)
        remove(script);

    auto p = pipeProcess([script]).sandbox.timeout(1.dur!"seconds").scopeKill;
    waitUntilChildren(p.osHandle, 1);
    const preChildren = makePidMap.getSubMap(p.osHandle).remove(p.osHandle).length;
    const res = p.process.drain(1.dur!"minutes").array;
    const postChildren = makePidMap.getSubMap(p.osHandle).remove(p.osHandle).length;

    p.wait.shouldEqual(-9);
    p.terminated.shouldBeTrue;
    preChildren.shouldEqual(1);
    postChildren.shouldEqual(0);
}

string makeScript(string script, string file = __FILE__, uint line = __LINE__) {
    import core.sys.posix.sys.stat;
    import std.file : getAttributes, setAttributes, thisExePath;
    import std.stdio : File;
    import std.path : baseName;
    import std.conv : to;

    immutable fname = thisExePath ~ "_" ~ file.baseName ~ line.to!string ~ ".sh";

    File(fname, "w").writeln(script);
    setAttributes(fname, getAttributes(fname) | S_IXUSR | S_IXGRP | S_IXOTH);
    return fname;
}

/// Wait for p to have num children or fail after 10s.
void waitUntilChildren(RawPid p, int num) {
    import std.datetime : Clock;

    const failAt = Clock.currTime + 10.dur!"seconds";
    do {
        Thread.sleep(50.dur!"msecs");
        if (Clock.currTime > failAt)
            break;
    }
    while (makePidMap.getSubMap(p).remove(p).length < num);
}
