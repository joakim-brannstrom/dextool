/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool_test.builders;

import scriptlike;

import std.datetime.stopwatch : StopWatch;
import std.range : isInputRange;
import std.typecons : Yes, No, Flag;
import std.traits : ReturnType;

static import core.thread;

import dextool_test.utils : escapePath;

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

        /// if the output from running the command should be yapped via scriptlike
        bool yap_output = true;

        /// if --debug is added to the arguments
        bool arg_debug = true;

        /// Throw an exception if the exit status is NOT zero
        bool throw_on_exit_status = true;
    }

    /**
     * Params:
     *  command = the executable to run
     *  workdir = directory to run the executable from
     */
    this(string dextool, string workdir) {
        this.dextool = dextool;
        this.workdir_ = workdir;
        this.test_outputdir = workdir;
    }

    Path workdir() {
        return Path(workdir_);
    }

    auto setWorkdir(T)(T v) {
        static if (is(T == string))
            workdir_ = v;
        else
            workdir_ = v.toString;
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
        this.args_ ~= v.escapePath;
        return this;
    }

    auto addInputArg(string v) {
        post_args ~= "--in=" ~ Path(v).escapePath;
        return this;
    }

    auto addInputArg(string[] v) {
        post_args ~= v.map!(a => Path(a)).map!(a => "--in=" ~ a.escapePath).array();
        return this;
    }

    auto addInputArg(Path v) {
        post_args ~= "--in=" ~ v.escapePath;
        return this;
    }

    auto addInputArg(Path[] v) {
        post_args ~= v.map!(a => "--in=" ~ a.escapePath).array();
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
        this.post_args ~= v.escapePath;
        return this;
    }

    /// Activate debugging mode of the dextool binary
    auto argDebug(bool v) {
        arg_debug = v;
        return this;
    }

    auto yapOutput(bool v) {
        yap_output = v;
        return this;
    }

    auto run() {
        import std.array : join;
        import std.algorithm : min;

        string[] cmd;
        cmd ~= dextool;
        cmd ~= args_.dup;
        cmd ~= post_args;
        cmd ~= "--out=" ~ workdir_;

        if (arg_debug) {
            cmd ~= "--debug";
        }

        if (flags_.length > 0) {
            cmd ~= "--";
            cmd ~= flags_.dup;
        }

        StopWatch sw;
        ReturnType!(std.process.tryWait) exit_;
        exit_.status = -1;
        Appender!(string[]) stdout_;
        Appender!(string[]) stderr_;

        sw.start;
        try {
            auto p = std.process.pipeProcess(cmd,
                    std.process.Redirect.stdout | std.process.Redirect.stderr);

            for (;;) {
                exit_ = std.process.tryWait(p.pid);

                foreach (l; p.stdout.byLineCopy)
                    stdout_.put(l);
                foreach (l; p.stderr.byLineCopy)
                    stderr_.put(l);

                if (exit_.terminated)
                    break;
                core.thread.Thread.sleep(20.msecs);
            }
            sw.stop;
        }
        catch (Exception e) {
            stderr_ ~= [e.msg];
            sw.stop;
        }

        auto rval = BuildCommandRunResult(exit_.status == 0, exit_.status,
                stdout_.data, stderr_.data, sw.peek.total!"msecs", cmd);
        if (yap_output) {
            auto f = File(nextFreeLogfile(test_outputdir), "w");
            f.writef("%s", rval);
        }

        if (throw_on_exit_status && exit_.status != 0) {
            auto l = min(10, stderr_.data.length);
            throw new ErrorLevelException(exit_.status, stderr_.data[0 .. l].join(newline));
        } else {
            return rval;
        }
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

        bool run_in_outdir;

        /// if the output from running the command should be yapped via scriptlike
        bool yap_output = true;

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

    auto args(string[] v) {
        this.args_ = v;
        return this;
    }

    auto addArg(string v) {
        this.args_ ~= v;
        return this;
    }

    auto addArg(Path v) {
        this.args_ ~= v.escapePath;
        return this;
    }

    auto addArg(string[] v) {
        this.args_ ~= v;
        return this;
    }

    auto addFileFromOutdir(string v) {
        this.args_ ~= buildPath(workdir_, v);
        return this;
    }

    auto yapOutput(bool v) {
        yap_output = v;
        return this;
    }

    auto run() {
        import std.path : buildPath;

        string[] cmd;
        if (run_in_outdir)
            cmd ~= buildPath(workdir.toString, command);
        else
            cmd ~= command;
        cmd ~= args_.dup;

        StopWatch sw;
        ReturnType!(std.process.tryWait) exit_;
        exit_.status = -1;
        Appender!(string[]) stdout_;
        Appender!(string[]) stderr_;

        sw.start;
        try {
            auto p = std.process.pipeProcess(cmd,
                    std.process.Redirect.stdout | std.process.Redirect.stderr);

            for (;;) {
                exit_ = std.process.tryWait(p.pid);

                foreach (l; p.stdout.byLineCopy)
                    stdout_.put(l);
                foreach (l; p.stderr.byLineCopy)
                    stderr_.put(l);

                if (exit_.terminated)
                    break;
                core.thread.Thread.sleep(10.msecs);
            }

            sw.stop;
        }
        catch (Exception e) {
            stderr_ ~= [e.msg];
            sw.stop;
        }

        auto rval = BuildCommandRunResult(exit_.status == 0, exit_.status,
                stdout_.data, stderr_.data, sw.peek.total!"msecs", cmd);
        if (yap_output) {
            auto f = File(nextFreeLogfile(workdir_), "w");
            f.writef("%s", rval);
        }

        if (throw_on_exit_status && exit_.status != 0) {
            auto l = min(10, stderr_.data.length);
            throw new ErrorLevelException(exit_.status, stderr_.data[0 .. l].join(newline));
        } else {
            return rval;
        }
    }
}

private auto nextFreeLogfile(string workdir) {
    import std.file : exists;
    import std.path : baseName, buildPath;
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
    string[] stdout;
    string[] stderr;
    /// time to execute the command. TODO: change to Duration after DMD v2.076
    const long executionMsecs;

    private string[] cmd;

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        import std.algorithm : joiner;
        import std.format : formattedWrite;
        import std.range.primitives : put;

        formattedWrite(w, "run: %s", cmd.dup.joiner(" "));
        put(w, newline);

        formattedWrite(w, "exit status: %s", status);
        put(w, newline);
        formattedWrite(w, "execution time ms: %s", executionMsecs);
        put(w, newline);

        put(w, "stdout:");
        put(w, newline);
        this.stdout.each!((a) { put(w, a); put(w, newline); });

        put(w, "stderr:");
        put(w, newline);
        this.stderr.each!((a) { put(w, a); put(w, newline); });
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
