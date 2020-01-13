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
    bool tryWait() @safe;

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

        pipe_.destroy;
        stderr_.destroy;
        this.kill;
        this.wait;
        process.destroy;
    }

    override void kill() nothrow @trusted {
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

    override int wait() @safe {
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

    override bool tryWait() @safe {
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

    override int status() @safe {
        if (st != State.exitCode) {
            throw new Exception(
                    "Process has not terminated and wait/tryWait been called to collect the exit status");
        }
        return status_;
    }

    override bool terminated() @safe {
        return st.among(State.terminated, State.exitCode) != 0;
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
        import core.sys.posix.unistd : setpgid;

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
        // this also reaps the children thus cleaning up zombies
        this.kill;
        p.destroy;
    }

    override void kill() nothrow @safe {
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

    override int wait() @safe {
        return p.wait;
    }

    override bool tryWait() @safe {
        return p.tryWait;
    }

    override int status() @safe {
        return p.status;
    }

    override bool terminated() @safe {
        return p.terminated;
    }
}

Sandbox sandbox(Process p) @safe {
    return new Sandbox(p);
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

    auto p = pipeProcess([scriptName]).sandbox.raii;
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

/** Terminate the process after the timeout. The timeout is checked in the
 * wait/tryWait methods.
 */
class Timeout : Process {
    import std.algorithm : among;
    import std.datetime : Clock, Duration;
    import std.concurrency;

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

        Process p;
        shared KillProcess kp;
        Tid background;
        Reply backgroundReply;
    }

    this(Process p, Duration timeout) @trusted {
        this.p = p;
        this.kp = cast(shared) new KillProcess(p);
        background = spawn(&checkProcess, p.osHandle, timeout, kp);
    }

    private static class KillProcess {
        import core.sync.mutex : Mutex;

        private {
            Process p;
            Mutex mtx;
        }
        this(Process p) {
            this.p = p;
            this.mtx = new Mutex();
        }

        void kill() @trusted nothrow {
            this.mtx.lock_nothrow();
            scope (exit)
                this.mtx.unlock_nothrow();
            p.kill;
        }
    }

    private static void checkProcess(RawPid p, Duration timeout, shared KillProcess kp) {
        import core.sys.posix.signal : SIGKILL;
        import std.algorithm : max;
        import std.variant : Variant;
        static import core.sys.posix.signal;

        const stopAt = Clock.currTime + timeout;
        // the purpose is to poll the process often "enough" that if it
        // terminates early `Process` detects it fast enough. 1000 is chosen
        // because it "feels good". the purpose
        auto sleepInterval = max(20, timeout.total!"msecs" / 1000).dur!"msecs";

        bool forceStop;
        Msg msg;
        while (!forceStop && Clock.currTime < stopAt) {
            msg = Msg.none;
            const hasMsg = receiveTimeout(sleepInterval, (Msg x) { msg = x; }, (Variant x) {
            },);

            final switch (msg) {
            case Msg.none:
                break;
            case Msg.stop:
                forceStop = true;
                break;
            case Msg.status:
                send(ownerTid, Reply.running);
                break;
            }

            if (!hasMsg && (core.sys.posix.signal.kill(p, 0) == -1)) {
                break;
            }
        }

        if (!forceStop && Clock.currTime >= stopAt) {
            (cast() kp).kill;
            send(ownerTid, Reply.killedByTimeout);
        } else {
            send(ownerTid, Reply.normalDeath);
        }
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

    override void destroy() @trusted {
        if (backgroundReply.among(Reply.none, Reply.running)) {
            send(background, Msg.stop);
            backgroundReply = receiveOnly!Reply;
        }
        p.destroy;
    }

    override void kill() nothrow @trusted {
        (cast() kp).kill;
    }

    override int wait() @trusted {
        while (!this.tryWait) {
            Thread.sleep(20.dur!"msecs");
        }
        return p.wait;
    }

    override bool tryWait() @safe {
        return p.tryWait;
    }

    override int status() @safe {
        return p.status;
    }

    override bool terminated() @safe {
        return p.terminated;
    }

    bool timeoutTriggered() @trusted {
        if (backgroundReply.among(Reply.none, Reply.running)) {
            send(background, Msg.status);
            backgroundReply = receiveOnly!Reply;
        }
        return backgroundReply == Reply.killedByTimeout;
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
    sw.peek.shouldBeSmallerThan(500.dur!"msecs");
    p.wait.shouldEqual(-9);
    p.terminated.shouldBeTrue;
    p.status.shouldEqual(-9);
    p.timeoutTriggered.shouldBeTrue;
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

    override bool tryWait() @safe {
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

    this(Process p) @safe pure nothrow @nogc {
        this.p = p;
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
                front_ = DrainElement(DrainElement.Type.stderr, p.stderr.read(4096));
            } else if (p.pipe.hasData && p.pipe.hasPendingData) {
                front_ = DrainElement(DrainElement.Type.stdout, p.pipe.read(4096));
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
DrainRange drain(Process p) @safe pure nothrow @nogc {
    return DrainRange(p);
}

/// Read the data from a ReadChannel by line.
struct DrainByLineCopyRange {
    private {
        Process process;
        DrainRange range;
        const(ubyte)[] buf;
        const(char)[] line;
    }

    this(Process p) @safe pure nothrow @nogc {
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

    auto p = pipeProcess(["dd", "if=/dev/zero", "bs=10", "count=3"]).raii;
    auto res = p.drainByLineCopy.filter!"!a.empty".array;

    res.length.shouldEqual(4);
    res.joiner.count.shouldBeGreaterThan(30);
    p.wait.shouldEqual(0);
    p.terminated.shouldBeTrue;
}

auto drainByLineCopy(Process p) @safe {
    return DrainByLineCopyRange(p);
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
    auto p = pipeProcess(["dd", "if=/dev/urandom", "bs=10", "count=3"]).raii;
    auto res = p.drain.array;

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

    auto p = pipeProcess([script]).sandbox.timeout(1.dur!"seconds").raii;
    for (int i = 0; getDeepChildren(p.osHandle).count < 1; ++i) {
        Thread.sleep(50.dur!"msecs");
    }
    const preChildren = getDeepChildren(p.osHandle).count;
    const res = p.drain.array;
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
