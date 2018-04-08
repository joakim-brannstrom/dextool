/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains process funtions to use session groups when running
processes.
*/
module dextool.plugin.mutate.backend.linux_process;

import core.sys.posix.unistd : pid_t;

enum KillResult {
    error,
    success
}

struct Wait {
    bool terminated;
    int status;
}

struct PidSession {
    import core.sys.posix.unistd : pid_t;

    enum Status {
        failed,
        active,
    }

    Status status;
    pid_t pid;

    @disable this(this);

    ~this() @safe nothrow @nogc {
        import core.sys.posix.signal : SIGKILL;

        killImpl(pid, SIGKILL);
    }
}

/** Fork to a new session and process group.
 *
 * The first index of args must be the path to the program.
 * The path must be absolute for the effect to be visible when running e.g. ps.
 *
 * trusted: the input and memory allocations use the GC and the facilities in D
 * to keep array's safe.
 *
 * Params:
 *  args = arguments to run.
 *  stdout_p = write stdout to this file (if null then /dev/null is used)
 *  stderr_p = write stderr to this file (if null then /dev/null is used)
 */
PidSession spawnSession(const char[][] args, string stdout_p = null,
        string stderr_p = null, bool debug_ = false) @trusted {
    import core.stdc.stdlib : exit;
    import core.sys.posix.unistd;
    import core.sys.posix.signal;
    import std.string : toStringz;
    import std.stdio : File;

    static import core.stdc.stdio;

    static int getFD(ref File f) {
        return core.stdc.stdio.fileno(f.getFP());
    }

    // running a compiler/make etc requires stdin/out/err
    auto stdin_ = File("/dev/null", "r");
    auto stdout_ = () {
        if (stdout_p.length == 0)
            return File("/dev/null", "w");
        else
            return File(stdout_p, "w");
    }();
    auto stderr_ = () {
        if (stderr_p.length == 0)
            return File("/dev/null", "w");
        else
            return File(stderr_p, "w");
    }();

    const(char*)* envz;

    try {
        envz = createEnv(null, true);
    }
    catch (Exception e) {
        return PidSession();
    }

    // use the GC before forking to avoid possible problems with deadlocks
    auto argz = new const(char)*[args.length + 1];
    foreach (i; 0 .. args.length)
        argz[i] = toStringz(args[i]);
    argz[$ - 1] = null;

    const pid_t parent = getpid();

    // NO GC after this point.
    auto pid = fork();
    if (pid < 0) {
        // failed to fork
        return PidSession();
    } else if (pid > 0) {
        // parent
        return PidSession(PidSession.Status.active, pid);
    }

    auto stdin_fd = getFD(stdin_);
    auto stdout_fd = getFD(stdout_);
    auto stderr_fd = getFD(stderr_);

    dup2(stdin_fd, STDIN_FILENO);
    dup2(stdout_fd, STDOUT_FILENO);
    dup2(stderr_fd, STDERR_FILENO);

    setCLOEXEC(STDIN_FILENO, false);
    setCLOEXEC(STDOUT_FILENO, false);
    setCLOEXEC(STDERR_FILENO, false);

    auto sid = setsid();
    if (sid < 0) {
        // unfortunately unable to inform the parent of the failure
        exit(-1);
        return PidSession();
    }

    // note: if a pre execve function are to be called do it here.

    auto sec_fork = fork();

    if (sec_fork < 0) {
        // failed to fork
        // unfortunately unable to inform the parent of the failure
        exit(-1);
    } else if (sec_fork == 0) {
        // child
        execve(argz[0], argz.ptr, envz);
    }

    const child = PidSession(PidSession.Status.active, sec_fork);

    // poll the parent process to detect if the group become orphaned.
    // suicide if it does.
    while (true) {
        if (parent != getppid()) {
            // parent changed so is orphaned
            import core.sys.posix.signal : SIGKILL;

            killImpl(child.pid, SIGKILL);
            killImpl(pid, SIGKILL);
            exit(-1); // should never happen
        }

        // check the child
        auto child_w = child.performWait(false);
        if (child_w.terminated)
            exit(child_w.status);

        usleep(100);
    }
}

/**
 * trusted: no memory is accessed thus no memory unsafe operations are
 * performed.
 */
private Wait performWait(const ref PidSession p, bool blocking) @trusted nothrow @nogc {
    import core.sys.posix.unistd;
    import core.sys.posix.sys.wait;
    import core.stdc.errno : errno, ECHILD;

    if (p.status != PidSession.Status.active)
        return Wait(true);

    int exitCode;

    while (true) {
        int status;
        auto check = waitpid(p.pid, &status, blocking ? 0 : WNOHANG);
        if (check == -1) {
            if (errno == ECHILD) {
                // process does not exist
                return Wait(true, 0);
            } else {
                // interrupted by a signal
                continue;
            }
        }

        if (!blocking && check == 0) {
            return Wait(false, 0);
        }

        if (WIFEXITED(status)) {
            exitCode = WEXITSTATUS(status);
            break;
        } else if (WIFSIGNALED(status)) {
            exitCode = -WTERMSIG(status);
            break;
        }

        if (!blocking)
            break;
    }

    return Wait(true, exitCode);
}

Wait tryWait(const ref PidSession p) @safe nothrow @nogc {
    return performWait(p, false);
}

Wait wait(const ref PidSession p) @safe nothrow @nogc {
    return performWait(p, true);
}

/**
 * trusted: no memory is manipulated thus it is memory safe.
 */
KillResult kill(const ref PidSession p, int signal) @trusted nothrow @nogc {
    if (p.status != PidSession.Status.active)
        return KillResult.error;

    return killImpl(p.pid, signal);
}

private KillResult killImpl(const pid_t p, int signal) @trusted nothrow @nogc {
    import core.sys.posix.signal : killpg;

    auto res = killpg(p, signal);
    return res == 0 ? KillResult.success : KillResult.error;
}

// COPIED FROM PHOBOS.
private extern (C) extern __gshared const char** environ;

// Made available by the C runtime:
private const(char**) getEnvironPtr() @trusted {
    return environ;
}

// Converts childEnv to a zero-terminated array of zero-terminated strings
// on the form "name=value", optionally adding those of the current process'
// environment strings that are not present in childEnv.  If the parent's
// environment should be inherited without modification, this function
// returns environ directly.
private const(char*)* createEnv(const string[string] childEnv, bool mergeWithParentEnv) @trusted {

    // Determine the number of strings in the parent's environment.
    int parentEnvLength = 0;
    auto environ = getEnvironPtr;
    if (mergeWithParentEnv) {
        if (childEnv.length == 0)
            return environ;
        while (environ[parentEnvLength] != null)
            ++parentEnvLength;
    }

    // Convert the "new" variables to C-style strings.
    auto envz = new const(char)*[parentEnvLength + childEnv.length + 1];
    int pos = 0;
    foreach (var, val; childEnv)
        envz[pos++] = (var ~ '=' ~ val ~ '\0').ptr;

    // Add the parent's environment.
    foreach (environStr; environ[0 .. parentEnvLength]) {
        int eqPos = 0;
        while (environStr[eqPos] != '=' && environStr[eqPos] != '\0')
            ++eqPos;
        if (environStr[eqPos] != '=')
            continue;
        auto var = environStr[0 .. eqPos];
        if (var in childEnv)
            continue;
        envz[pos++] = environStr;
    }
    envz[pos] = null;
    return envz.ptr;
}

// Sets or unsets the FD_CLOEXEC flag on the given file descriptor.
private void setCLOEXEC(int fd, bool on) nothrow @nogc {
    import core.stdc.errno : errno, EBADF;
    import core.sys.posix.fcntl : fcntl, F_GETFD, FD_CLOEXEC, F_SETFD;

    auto flags = fcntl(fd, F_GETFD);
    if (flags >= 0) {
        if (on)
            flags |= FD_CLOEXEC;
        else
            flags &= ~(cast(typeof(flags)) FD_CLOEXEC);
        flags = fcntl(fd, F_SETFD, flags);
    }
    assert(flags != -1 || errno == EBADF);
}
