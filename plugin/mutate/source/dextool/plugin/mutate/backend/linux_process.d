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

        kill(this, SIGKILL);
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
 */
PidSession spawnSession(const char[][] args, bool debug_ = false) @trusted nothrow {
    import core.stdc.stdlib;
    import core.sys.posix.unistd;
    import core.sys.posix.signal;
    import std.string : toStringz;

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

    // NO GC after this point.
    auto pid = fork();
    if (pid < 0) {
        // failed to fork
        return PidSession();
    } else if (pid > 0) {
        // parent
        return PidSession(PidSession.Status.active, pid);
    }

    if (!debug_) {
        close(0);
        close(1);
        close(2);
    }

    auto sid = setsid();
    if (sid < 0) {
        // unfortantly unable to inform the parent of the failure
        exit(-1);
        return PidSession();
    }

    // note: if a pre execve function are to be called do it here.

    execve(argz[0], argz.ptr, envz);

    // dummy, this is never reached.
    return PidSession();
}

struct Wait {
    bool terminated;
    int status;
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

enum KillResult {
    error,
    success
}

/**
 * trusted: no memory is manipulated thus it is memory safe.
 */
KillResult kill(const ref PidSession p, int signal) @trusted nothrow @nogc {
    import core.sys.posix.unistd;
    import core.sys.posix.signal;
    import core.stdc.errno : errno, EINVAL, EPERM, ESRCH;

    if (p.status != PidSession.Status.active)
        return KillResult.error;

    auto sid = getpgid(p.pid);
    return killpg(sid, signal) == 0 ? KillResult.success : KillResult.error;
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
