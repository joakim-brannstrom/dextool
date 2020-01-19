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
import std.algorithm : filter, count, joiner, map;
import std.array : appender, empty, array;
import std.exception : collectException;
import std.stdio : File, fileno, writeln;
static import std.process;

public import process.channel;

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

struct Process(T) {
    T process;

    /// Access to stdin and stdout.
    Channel pipe() nothrow @safe {
        return process.pipe;
    }

    /// Access stderr.
    ReadChannel stderr() nothrow @safe {
        return process.stderr;
    }

    /// Kill and cleanup the process.
    void dispose() @safe {
        process.dispose;
    }

    /// Kill the process.
    void kill() nothrow @safe {
        process.kill;
    }

    /// Blocking wait for the process to terminated.
    /// Returns: the exit status.
    int wait() @safe {
        return process.wait;
    }

    /// Non-blocking wait for the process termination.
    /// Returns: `true` if the process has terminated.
    bool tryWait() @safe {
        return process.tryWait;
    }

    /// Returns: The raw OS handle for the process ID.
    RawPid osHandle() nothrow @safe {
        return process.osHandle;
    }

    /// Returns: The exit status of the process.
    int status() @safe {
        return process.status;
    }

    /// Returns: If the process has terminated.
    bool terminated() nothrow @safe;
}

/** Async process that do not block on read from stdin/stderr.
 */
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
        ReadChannel stderr_;
        int status_;
        State st;
    }

    this(std.process.ProcessPipes process) @safe {
        this.process = process;
        this.pipe_ = new Pipe(this.process.stdout, this.process.stdin);
        this.stderr_ = new FileReadChannel(this.process.stderr);
    }

    RawPid osHandle() nothrow @safe {
        return process.pid.osHandle.RawPid;
    }

    Channel pipe() nothrow @safe {
        return pipe_;
    }

    ReadChannel stderr() nothrow @safe {
        return stderr_;
    }

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

        pipe_.dispose;
        pipe_ = null;

        stderr_.dispose;
        stderr_ = null;

        st = State.exitCode;
    }

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

    int status() @safe {
        if (st != State.exitCode) {
            throw new Exception(
                    "Process has not terminated and wait/tryWait been called to collect the exit status");
        }
        return status_;
    }

    bool terminated() @safe {
        return st.among(State.terminated, State.exitCode) != 0;
    }
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
    }

    this(ProcessT p) @safe {
        import core.sys.posix.unistd : setpgid;

        this.p = p;
        setpgid(p.osHandle, 0);
    }

    RawPid osHandle() nothrow @safe {
        return p.osHandle;
    }

    Channel pipe() nothrow @safe {
        return p.pipe;
    }

    ReadChannel stderr() nothrow @safe {
        return p.stderr;
    }

    void dispose() @safe {
        // this also reaps the children thus cleaning up zombies
        this.kill;
        p.dispose;
    }

    void kill() nothrow @safe {
        static import core.sys.posix.signal;
        import core.sys.posix.sys.wait : waitpid, WNOHANG;

        static RawPid[] update(RawPid[] pids) @trusted {
            auto app = appender!(RawPid[])();

            foreach (p; pids) {
                try {
                    app.put(getDeepChildren(p));
                } catch (Exception e) {
                }
            }

            return app.data;
        }

        static void killChildren(RawPid[] children) @trusted {
            foreach (const c; children) {
                core.sys.posix.signal.kill(c, core.sys.posix.signal.SIGKILL);
            }
        }

        p.kill;
        auto children = update([p.osHandle]);
        auto reapChildren = appender!(RawPid[])();
        // if there ever are processes that are spawned with root permissions
        // or something happens that they can't be killed by "this" process
        // tree. Thus limit the iterations to a reasonable number
        for (int i = 0; !children.empty && i < 5; ++i) {
            reapChildren.put(children);
            killChildren(children);
            children = update(children);
        }

        foreach (c; reapChildren.data) {
            () @trusted { waitpid(c, null, WNOHANG); }();
        }
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
    import std.algorithm : count;
    import std.datetime.stopwatch : StopWatch, AutoStart;

    immutable scriptName = makeScript(`#!/bin/bash
sleep 10m &
sleep 10m &
sleep 10m
`);
    scope (exit)
        remove(scriptName);

    auto p = pipeProcess([scriptName]).sandbox.scopeKill;
    for (int i = 0; getDeepChildren(p.osHandle).count < 3; ++i) {
        Thread.sleep(50.dur!"msecs");
    }
    const preChildren = getDeepChildren(p.osHandle).count;
    p.kill;
    Thread.sleep(500.dur!"msecs"); // wait for the OS to kill the children
    const postChildren = getDeepChildren(p.osHandle).count;

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
            Background background;
            Reply backgroundReply;
        }

        RefCounted!Payload rc;
    }

    this(ProcessT p, Duration timeout) @trusted {
        import std.algorithm : move;

        rc = refCounted(Payload(move(p)));
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

        this(ProcessT* p, Duration timeout) {
            this.p = p;
            this.timeout = timeout;
            this.mtx = new Mutex();

            super(&run);
        }

        void run() {
            checkProcess(p.osHandle, this.timeout, this);
        }

        void put(Msg msg) @trusted {
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

        void setReply(Reply reply_) @trusted {
            {
                this.mtx.lock_nothrow();
                scope (exit)
                    this.mtx.unlock_nothrow();
                this.reply_ = reply_;
            }
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

    private static void checkProcess(RawPid p, Duration timeout, Background bg) {
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

        if (!forceStop && Clock.currTime >= stopAt) {
            bg.kill;
            bg.setReply(Reply.killedByTimeout);
        } else {
            bg.setReply(Reply.normalDeath);
        }
    }

    RawPid osHandle() nothrow @trusted {
        return rc.p.osHandle;
    }

    Channel pipe() nothrow @trusted {
        return rc.p.pipe;
    }

    ReadChannel stderr() nothrow @trusted {
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
        ProcessT p;
        DrainElement front_;
        State st;
        ubyte[] buf;
        ubyte[] bufRead;
    }

    this(ProcessT p) {
        this.p = p;
        this.buf = new ubyte[4096];
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
            if (p.stderr.hasData && p.stderr.hasPendingData) {
                front_ = DrainElement(DrainElement.Type.stderr);
                bufRead = p.stderr.read(buf);
            } else if (p.pipe.hasData && p.pipe.hasPendingData) {
                front_ = DrainElement(DrainElement.Type.stdout);
                bufRead = p.pipe.read(buf);
            }
        }

        void waitUntilData() @safe {
            while (bufRead.empty && isAnyPipeOpen) {
                import core.thread : Thread;
                import core.time : dur;

                readData();
                if (front_.data.empty) {
                    () @trusted { Thread.sleep(20.dur!"msecs"); }();
                }
            }
            front_.data = bufRead.dup;
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
            st = State.lastStderr;
            readData();
            if (p.pipe.hasData) {
                st = State.lastStdout;
            }
            break;
        case State.lastStderr:
            st = State.lastElement;
            readData();
            if (p.stderr.hasData) {
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
auto drain(T)(T p) {
    return DrainRange!T(p);
}

/// Read the data from a ReadChannel by line.
struct DrainByLineCopyRange(ProcessT) {
    private {
        ProcessT process;
        DrainRange!ProcessT range;
        const(ubyte)[] buf;
        const(char)[] line;
    }

    this(ProcessT p) @safe {
        process = p;
        range = p.drain;
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
    import std.algorithm : filter, count, joiner, map;
    import std.array : array;

    auto p = pipeProcess(["dd", "if=/dev/zero", "bs=10", "count=3"]).scopeKill;
    auto res = p.process.drainByLineCopy.filter!"!a.empty".array;

    res.length.shouldEqual(4);
    res.joiner.count.shouldBeGreaterThan(30);
    p.wait.shouldEqual(0);
    p.terminated.shouldBeTrue;
}

auto drainByLineCopy(T)(T p) @safe {
    return DrainByLineCopyRange!T(p);
}

/// Drain the process output until it is done executing.
auto drainToNull(T)(T p) @safe {
    foreach (l; p.drain) {
    }
    return p;
}

/// Drain the output from the process into an output range.
auto drain(ProcessT, T)(ProcessT p, ref T range) {
    foreach (l; p.drain) {
        range.put(l);
    }
    return p;
}

@("shall drain the output of a process while it is running with a separation of stdout and stderr")
unittest {
    auto p = pipeProcess(["dd", "if=/dev/urandom", "bs=10", "count=3"]).scopeKill;
    auto res = p.process.drain.array;

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
    for (int i = 0; getDeepChildren(p.osHandle).count < 1; ++i) {
        Thread.sleep(50.dur!"msecs");
    }
    const preChildren = getDeepChildren(p.osHandle).count;
    const res = p.process.drain.array;
    const postChildren = getDeepChildren(p.osHandle).count;

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
