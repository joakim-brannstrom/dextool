/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool_test.builders;

import core.time : dur;
import logger = std.experimental.logger;
import std.algorithm : map, joiner;
import std.array : array, Appender, appender, empty;
import std.datetime.stopwatch : StopWatch, AutoStart, Duration, dur;
import std.path : buildPath;
import std.range : isInputRange;
import std.stdio : File;
import std.string : join;

import dextool_test.types;

/** Build the command line arguments and working directory to use when invoking
 * dextool.
 */
struct BuildDextoolRun {
    import std.ascii : newline;

    private {
        string dextool;
        string workdir_;
        string test_outputdir;
        string[] args_;
        string[] post_args;
        string[] flags_;

        /// Data to stream into stdin upon execute.
        string stdin_data;

        /// if --debug is added to the arguments
        bool arg_debug = true;

        /// Throw an exception if the exit status is NOT zero
        bool throw_on_exit_status = true;
    }

    /**
     * Params:
     *  dextool = the executable to run
     *  workdir = directory to run the executable from
     */
    this(string dextool, string workdir) {
        this.dextool = dextool;
        this.workdir_ = workdir;
        this.test_outputdir = workdir;
    }

    this(Path dextool, Path workdir) {
        this(dextool.toString, workdir.toString);
    }

    Path workdir() {
        return Path(workdir_);
    }

    auto setWorkdir(T)(T v) {
        static if (is(T == string))
            workdir_ = v;
        else static if (is(T == typeof(null)))
            workdir_ = null;
        else
            workdir_ = v.toString;
        return this;
    }

    auto setStdin(string v) {
        this.stdin_data = v;
        return this;
    }

    auto throwOnExitStatus(bool v) {
        this.throw_on_exit_status = v;
        return this;
    }

    auto flags(string[] v) {
        this.flags_ = v;
        return this;
    }

    auto addFlag(T)(T v) {
        this.flags_ ~= v;
        return this;
    }

    auto addDefineFlag(string v) {
        this.flags_ ~= ["-D", v];
        return this;
    }

    auto addIncludeFlag(string v) {
        this.flags_ ~= ["-I", v];
        return this;
    }

    auto addIncludeFlag(Path v) {
        this.flags_ ~= ["-I", v.toString];
        return this;
    }

    auto args(string[] v) {
        this.args_ = v;
        return this;
    }

    auto addArg(T)(T v) {
        this.args_ ~= v;
        return this;
    }

    auto addArg(Path v) {
        this.args_ ~= v.toString;
        return this;
    }

    auto addInputArg(string v) {
        post_args ~= ["--in", v];
        return this;
    }

    auto addInputArg(string[] v) {
        post_args ~= v.map!(a => ["--in", a]).joiner.array();
        return this;
    }

    auto addInputArg(Path v) {
        post_args ~= ["--in", v.toString];
        return this;
    }

    auto addInputArg(Path[] v) {
        post_args ~= v.map!(a => ["--in", a.toString]).joiner.array();
        return this;
    }

    auto postArg(string[] v) {
        this.post_args = v;
        return this;
    }

    auto addPostArg(T)(T v) {
        this.post_args ~= v;
        return this;
    }

    auto addPostArg(Path v) {
        this.post_args ~= v.toString;
        return this;
    }

    /// Activate debugging mode of the dextool binary
    auto argDebug(bool v) {
        arg_debug = v;
        return this;
    }

    auto run() {
        import process;

        auto cmd = () {
            string[] cmd;
            cmd ~= dextool;
            cmd ~= args_.dup;
            cmd ~= post_args;
            if (workdir_.length != 0)
                cmd ~= ["--out=", workdir_];

            if (arg_debug) {
                cmd ~= "--debug";
            }

            if (flags_.length > 0) {
                cmd ~= "--";
                cmd ~= flags_.dup;
            }
            return cmd;
        }();

        auto log = File(nextFreeLogfile(test_outputdir), "w");
        log.writefln("run: %-(%s %)", cmd);
        log.writeln("output:");
        int exit_status = -1;
        auto output = appender!(string[])();

        auto sw = StopWatch(AutoStart.yes);
        try {
            auto p = pipeProcess(cmd).sandbox.scopeKill;
            if (!stdin_data.empty) {
                p.pipe.write(cast(const(ubyte)[]) stdin_data);
                p.pipe.closeWrite;
            }

            foreach (e; p.process.drainByLineCopy(1.dur!"hours")) {
                log.writeln(e);
                log.flush;
                output.put(e);
            }
            exit_status = p.wait;
        } catch (Exception e) {
            output.put(e.msg);
            log.writeln(e.msg);
        }
        sw.stop;

        log.writeln("exit status: ", exit_status);
        log.writeln("execution time: ", sw.peek);

        auto rval = BuildCommandRunResult(exit_status == 0, exit_status,
                output.data, sw.peek, cmd);

        if (throw_on_exit_status && exit_status != 0) {
            throw new ErrorLevelException(exit_status, output.data.join(newline));
        }
        return rval;
    }
}

/** Build the command line arguments and working directory to use when invoking
 * a command.
 */
struct BuildCommandRun {
    import std.ascii : newline;

    private {
        string command;
        string workdir_;
        string[] args_;
        string[] post_args;

        /// Data to stream into stdin upon execute.
        string stdin_data;

        bool run_in_outdir;

        /// Throw an exception if the exit status is NOT zero
        bool throw_on_exit_status = true;
    }

    this(string command) {
        this.command = command;
        run_in_outdir = false;
    }

    /**
     * Params:
     *  command = the executable to run
     *  workdir = directory to run the executable from
     */
    this(string command, string workdir) {
        this.command = command;
        this.workdir_ = workdir;
        run_in_outdir = true;
    }

    this(string command, Path workdir) {
        this(command, workdir.toString);
    }

    Path workdir() {
        return Path(workdir_);
    }

    auto setWorkdir(Path v) {
        workdir_ = v.toString;
        return this;
    }

    /// If the command to run is in workdir.
    auto commandInOutdir(bool v) {
        run_in_outdir = v;
        return this;
    }

    auto throwOnExitStatus(bool v) {
        this.throw_on_exit_status = v;
        return this;
    }

    auto setStdin(string v) {
        this.stdin_data = v;
        return this;
    }

    auto args(string[] v) {
        this.args_ = v;
        return this;
    }

    auto postArgs(string[] v) {
        this.post_args = v;
        return this;
    }

    auto addArg(string v) {
        this.args_ ~= v;
        return this;
    }

    auto addArg(Path v) {
        this.args_ ~= v.toString;
        return this;
    }

    auto addArg(string[] v) {
        this.args_ ~= v;
        return this;
    }

    auto addPostArg(string v) {
        this.post_args ~= v;
        return this;
    }

    auto addPostArg(Path v) {
        this.post_args ~= v.toString;
        return this;
    }

    auto addPostArg(string[] v) {
        this.post_args ~= v;
        return this;
    }

    auto addFileFromOutdir(string v) {
        this.args_ ~= buildPath(workdir_, v);
        return this;
    }

    auto run() {
        import process;

        auto cmd = () {
            string[] cmd;
            if (run_in_outdir)
                cmd ~= buildPath(workdir.toString, command);
            else
                cmd ~= command;
            cmd ~= args_.dup;
            cmd ~= post_args;
            return cmd;
        }();

        auto log = File(nextFreeLogfile(workdir_), "w");
        log.writefln("run: %-(%s %)", cmd);
        log.writeln("output:");
        int exit_status = -1;
        auto output = appender!(string[])();

        auto sw = StopWatch(AutoStart.yes);
        try {
            auto p = pipeProcess(cmd).sandbox.scopeKill;
            if (!stdin_data.empty) {
                p.pipe.write(cast(const(ubyte)[]) stdin_data);
                p.pipe.closeWrite;
            }

            foreach (e; p.process.drainByLineCopy(1.dur!"hours")) {
                log.writeln(e);
                log.flush;
                output.put(e);
            }
            exit_status = p.wait;
        } catch (Exception e) {
            output.put(e.msg);
        }
        sw.stop;

        log.writeln("exit status: ", exit_status);
        log.writeln("execution time: ", sw.peek);

        auto rval = BuildCommandRunResult(exit_status == 0, exit_status,
                output.data, sw.peek, cmd);

        if (throw_on_exit_status && exit_status != 0) {
            throw new ErrorLevelException(exit_status, output.data.join(newline));
        } else {
            return rval;
        }
    }
}

private auto nextFreeLogfile(string workdir) {
    import std.file : exists;
    import std.path : baseName;
    import std.string : format;

    int idx;
    string f;
    do {
        f = buildPath(workdir, format("run_command%s.log", idx));
        ++idx;
    }
    while (exists(f));

    return f;
}

struct BuildCommandRunResult {
    import std.ascii : newline;
    import std.format : FormatSpec;

    /// convenient value which is true when exit status is zero.
    const bool success;
    /// actual exit status
    const int status;
    /// captured output
    string[] output;
    /// time to execute the command. TODO: change to Duration after DMD v2.076
    const Duration time;

    private string[] cmd;

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        import std.format : formattedWrite;
        import std.range.primitives : put;

        formattedWrite(w, "run: %s", cmd.dup.joiner(" "));
        put(w, newline);

        formattedWrite(w, "exit status: %s", status);
        put(w, newline);
        formattedWrite(w, "execution time ms: %s", time);
        put(w, newline);

        put(w, "output:");
        put(w, newline);
        foreach (l; output) {
            put(w, l);
            put(w, newline);
        }
    }

    string toString() @safe pure const {
        import std.exception : assumeUnique;
        import std.format : FormatSpec;

        char[] buf;
        buf.reserve(100);
        auto fmt = FormatSpec!char("%s");
        toString((const(char)[] s) { buf ~= s; }, fmt);
        auto trustedUnique(T)(T t) @trusted {
            return assumeUnique(t);
        }

        return trustedUnique(buf);
    }
}
