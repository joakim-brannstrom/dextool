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

import std.range : isInputRange;
import std.typecons : Yes, No, Flag;

import dextool_test.utils : escapePath;

struct BuildDextoolRun {
    import std.ascii : newline;

    private {
        string dextool;
        string outdir;
        string[] args_;
        string[] flags_;

        /// if the output from running the command should be yapped via scriptlike
        bool yap_output = true;

        /// if --debug is added to the arguments
        bool arg_debug = true;

        /// Throw an exception if the exit status is NOT zero
        bool throw_on_exit_status = true;
    }

    this(string dextool, string outdir) {
        this.dextool = dextool;
        this.outdir = outdir;
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

    auto addInputArg(string v) {
        args_ ~= "--in=" ~ Path(v).escapePath;
        return this;
    }

    auto addInputArg(string[] v) {
        args_ ~= v.map!(a => Path(a)).map!(a => "--in=" ~ a.escapePath).array();
        return this;
    }

    auto addInputArg(Path v) {
        args_ ~= "--in=" ~ v.escapePath;
        return this;
    }

    auto addInputArg(Path[] v) {
        args_ ~= v.map!(a => "--in=" ~ a.escapePath).array();
        return this;
    }

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
        cmd ~= "--out=" ~ outdir;

        if (arg_debug) {
            cmd ~= "--debug";
        }

        if (flags_.length > 0) {
            cmd ~= "--";
            cmd ~= flags_.dup;
        }

        import std.datetime;

        StopWatch sw;
        int exit_status = -1;
        Appender!(string[]) stdout_;
        Appender!(string[]) stderr_;

        sw.start;
        try {
            auto p = std.process.pipeProcess(cmd,
                    std.process.Redirect.stdout | std.process.Redirect.stderr);

            foreach (l; p.stdout.byLineCopy)
                stdout_.put(l);
            foreach (l; p.stderr.byLineCopy)
                stderr_.put(l);

            exit_status = std.process.wait(p.pid);
            sw.stop;

            // TODO I think this is needed to ensure the pipes are flushed
            foreach (l; p.stdout.byLineCopy)
                stdout_.put(l);
            foreach (l; p.stderr.byLineCopy)
                stderr_.put(l);
        }
        catch (Exception e) {
            stderr_ ~= [e.msg];
            sw.stop;
        }

        auto rval = BuildCommandRunResult(exit_status == 0, exit_status,
                stdout_.data, stderr_.data, sw.peek.msecs, cmd);
        if (yap_output) {
            auto f = File(nextFreeLogfile(outdir), "w");
            f.writef("%s", rval);
        }

        if (throw_on_exit_status && exit_status != 0) {
            auto l = min(10, stderr_.data.length);
            throw new ErrorLevelException(exit_status, stderr_.data[0 .. l].join(newline));
        } else {
            return rval;
        }
    }
}

struct BuildCommandRun {
    import std.ascii : newline;

    private {
        string command;
        string outdir_;
        string[] args_;

        /// if the output from running the command should be yapped via scriptlike
        bool yap_output = true;

        /// Throw an exception if the exit status is NOT zero
        bool throw_on_exit_status = true;
    }

    this(string command, string outdir) {
        this.command = command;
        this.outdir_ = outdir;
    }

    Path outdir() {
        return Path(outdir_);
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
        this.args_ ~= buildPath(outdir_, v);
        return this;
    }

    auto yapOutput(bool v) {
        yap_output = v;
        return this;
    }

    auto run() {
        string[] cmd;
        cmd ~= command;
        cmd ~= args_.dup;

        import std.datetime;

        StopWatch sw;
        int exit_status = -1;
        Appender!(string[]) stdout_;
        Appender!(string[]) stderr_;

        sw.start;
        try {
            auto p = std.process.pipeProcess(cmd,
                    std.process.Redirect.stdout | std.process.Redirect.stderr);

            foreach (l; p.stdout.byLineCopy)
                stdout_.put(l);
            foreach (l; p.stderr.byLineCopy)
                stderr_.put(l);

            exit_status = std.process.wait(p.pid);
            sw.stop;

            // TODO I think this is needed to ensure the pipes are flushed
            foreach (l; p.stdout.byLineCopy)
                stdout_.put(l);
            foreach (l; p.stderr.byLineCopy)
                stderr_.put(l);
        }
        catch (Exception e) {
            stderr_ ~= [e.msg];
            sw.stop;
        }

        auto rval = BuildCommandRunResult(exit_status == 0, exit_status,
                stdout_.data, stderr_.data, sw.peek.msecs, cmd);
        if (yap_output) {
            auto f = File(nextFreeLogfile(outdir_), "w");
            f.writef("%s", rval);
        }

        if (throw_on_exit_status && exit_status != 0) {
            auto l = min(10, stderr_.data.length);
            throw new ErrorLevelException(exit_status, stderr_.data[0 .. l].join(newline));
        } else {
            return rval;
        }
    }
}

private auto nextFreeLogfile(string outdir) {
    import std.file : exists;
    import std.path : baseName;
    import std.string : format;

    int idx;
    string f;
    do {
        f = buildPath(outdir, format("run_command%s.log", idx));
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
    const string[] stdout;
    const string[] stderr;
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
