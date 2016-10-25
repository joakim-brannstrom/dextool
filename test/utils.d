/**
Copyright: Copyright (c) 2015-2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module utils;
import scriptlike;

import std.typecons : Yes, No, Flag;

enum dextoolExePath = "../build/dextool-debug";

private void delegate(string) oldYap = null;
private string[] yapLog;

static this() {
    scriptlikeCustomEcho = (string s) => dextoolYap(s);
    echoOn;
}

void dextoolYap(string msg) nothrow {
    yapLog ~= msg;
}

void dextoolYap(T...)(T args) {
    import std.format : format;

    yapLog ~= format(args);
}

string[] getYapLog() {
    return yapLog.dup;
}

void resetYapLog() {
    yapLog.length = 0;
}

void echoOn() {
    .scriptlikeEcho = true;
}

void echoOff() {
    .scriptlikeEcho = false;
}

string escapePath(in Path p) {
    import scriptlike : escapeShellArg;

    return p.toRawString.dup.escapeShellArg;
}

void runAndLog(string args) {
    import std.algorithm : max;

    auto status = tryRunCollect(args);

    yap("Exit status: ", status.status);
    yap(status.output);
    if (status.status != 0) {
        auto l = min(100, status.output.length);

        throw new ErrorLevelException(status.status, status.output[0 .. l].dup);
    }
}

struct TestEnv {
    import std.ascii : newline;

    private Path outdir_;
    private Path dextool_;
    private File logfile;

    this(Path dextool) {
        this.dextool_ = dextool.absolutePath;
    }

    Path outdir() const {
        return outdir_;
    }

    Path dextool() const {
        return dextool_;
    }

    string toString() {
        // dfmt off
        return only(
                    ["dextool:", dextool.toString],
                    ["outdir:", outdir.toString],
                    )
            .map!(a => leftJustifier(a[0], 10).text ~ a[1])
            .joiner(newline)
            .text;
        // dfmt on
    }

    void setup(Path outdir__) {
        outdir_ = outdir__.absolutePath.stripExtension;
        yap("Test environment:", newline, toString);

        // ensure logs are empty
        if (exists(outdir)) {
            // tryRemove can fail, usually duo to I/O when tests are ran in
            // parallel.
            try {
                dirEntries(outdir, SpanMode.shallow).each!(a => tryRemove(Path(a)));
            }
            catch (FileException ex) {
                yap(ex.msg);
            }
        } else {
            mkdirRecurse(outdir);
        }

        auto stdout_path = outdir ~ "stdout.log";
        logfile = File(stdout_path.toString, "w");
    }

    void teardown() {
        if (!logfile.isOpen) {
            return;
        }

        // Use when saving error data for later analyze
        foreach (l; getYapLog) {
            logfile.writeln(l);
        }

        resetYapLog();

        logfile.close();
    }
}

string EnvSetup(string logdir) {
    import std.format : format;

    auto txt = `
    import scriptlike;

    auto testEnv = TestEnv(Path("%s"));

    // Setup and cleanup
    scope (exit) {
        testEnv.teardown();
    }
    chdir(thisExePath.dirName);

    {
        import std.traits : fullyQualifiedName;
        int _ = 0;
        testEnv.setup(Path("%s/" ~ fullyQualifiedName!_));
    }
`;

    return format(txt, dextoolExePath, logdir);
}

struct GR {
    Path gold;
    Path result;
}

/** Sorted compare of gold and result.
 *
 * max_diff is arbitrarily chosen to 5.
 * The purpose is to limit the amount of text that is dumped.
 * The reasoning is that it is better to give more than one line as feedback.
 */
void compare(in Path gold, in Path result, Flag!"sortLines" sortLines) {
    import std.algorithm : joiner, map;
    import std.stdio : File;
    import std.utf : toUTF8;

    yap("Comparing gold:", gold.toRawString);
    yap("        result:", result.toRawString);

    File goldf;
    File resultf;

    try {
        goldf = File(gold.escapePath);
        resultf = File(result.escapePath);
    }
    catch (ErrnoException ex) {
        throw new ErrorLevelException(-1, ex.msg);
    }

    auto maybeSort(T)(T lines) {
        import std.array : array;
        import std.algorithm : sort;

        if (sortLines) {
            return sort!((a, b) => a[1] < b[1])(lines.array()).array();
        }

        return lines.array();
    }

    bool diff_detected = false;
    immutable max_diff = 5;
    int accumulated_diff;
    foreach (g, r; lockstep(maybeSort(goldf.byLine().map!(a => a.toUTF8)
            .enumerate), maybeSort(resultf.byLine().map!(a => a.toUTF8).enumerate))) {
        if (g[1].strip.length > 2 && r[1].strip.length > 2
                && g[1].strip[0 .. 2] == "//" && r[1].strip[0 .. 2] == "//") {
            continue;
        } else if (g[1] != r[1] && accumulated_diff < max_diff) {
            // +1 of index because editors start counting lines from 1
            yap("Line ", g[0] + 1, " gold:", g[1]);
            yap("Line ", r[0] + 1, "  out:", r[1], "\n");
            diff_detected = true;
            ++accumulated_diff;
        }
    }

    //TODO replace with enforce
    if (diff_detected) {
        yap("Output is different from reference file (gold): " ~ gold.escapePath);
        throw new ErrorLevelException(-1,
                "Output is different from reference file (gold): " ~ gold.escapePath);
    }
}

bool stdoutContains(in string txt) {
    import std.string : indexOf;

    return getYapLog().joiner().array().indexOf(txt) != -1;
}

import std.range : isInputRange;

bool stdoutContains(T)(in T gold_lines) if (isInputRange!T) {
    import std.array : array;
    import std.range : enumerate;
    import std.traits : isArray;

    enum ContainState {
        NotFoundFirstLine,
        Comparing,
        BlockFound,
        BlockNotFound
    }

    ContainState state;

    auto result_lines = getYapLog().map!(a => a.splitLines).joiner().array();
    size_t gold_idx, result_idx;
    while (!state.among(ContainState.BlockFound, ContainState.BlockNotFound)) {
        string result_line;
        if (result_idx < result_lines.length) {
            result_line = result_lines[result_idx];
        }

        switch (state) with (ContainState) {
        case NotFoundFirstLine:
            if (gold_lines[0].strip == result_line.strip) {
                state = Comparing;
                ++gold_idx;
            } else if (result_lines.length == result_idx) {
                state = BlockNotFound;
            }
            break;
        case Comparing:
            if (gold_lines.length == gold_idx) {
                state = BlockFound;
            } else if (result_lines.length == result_idx) {
                state = BlockNotFound;
            } else if (gold_lines[gold_idx].strip != result_line.strip) {
                state = BlockNotFound;
            }

            ++gold_idx;
            break;
        default:
        }

        if (state == ContainState.BlockNotFound && result_lines.length == result_idx) {
            yap("Error: Stdout do not contain the reference file");
            yap("Expected: " ~ gold_lines[0]);
        } else if (state == ContainState.BlockNotFound) {
            yap("Error: Difference from reference file. Line ", gold_idx);
            yap("Expected: " ~ gold_lines[gold_idx]);
            yap("  Actual: " ~ result_line);
        }

        if (state.among(ContainState.BlockFound, ContainState.BlockNotFound)) {
            break;
        }

        ++result_idx;
    }

    return state == ContainState.BlockFound;
}

/// Check if the logged stdout contains the golden block.
///TODO refactor function. It is unnecessarily complex.
bool stdoutContains(in Path gold) {
    import std.array : array;
    import std.range : enumerate;
    import std.stdio : File;

    yap("Contains gold:", gold.toRawString);

    File goldf;

    try {
        goldf = File(gold.escapePath);
    }
    catch (ErrnoException ex) {
        yap(ex.msg);
        return false;
    }

    bool status = stdoutContains(goldf.byLine.array());

    if (!status) {
        yap("Output do not contain the reference file (gold): " ~ gold.escapePath);
        return false;
    }

    return true;
}

/** Run dextool.
 *
 * Return: The runtime in ms.
 */
auto runDextool(T)(in T input, const ref TestEnv testEnv, in string[] pre_args, in string[] flags) {
    import std.traits : isArray;

    Args args;
    args ~= testEnv.dextool;
    args ~= pre_args.dup;
    args ~= "--out=" ~ testEnv.outdir.escapePath;

    static if (isArray!T) {
        foreach (f; input) {
            args ~= "--in=" ~ f.escapePath;
        }
    } else {
        if (input.escapePath.length > 0) {
            args ~= "--in=" ~ input.escapePath;
        }
    }

    if (flags.length > 0) {
        args ~= "--";
        args ~= flags.dup;
    }

    import std.datetime;

    StopWatch sw;
    sw.start;
    runAndLog(args.data);
    sw.stop;

    yap("Dextool execution time in ms: " ~ sw.peek().msecs.text);
    return sw.peek.msecs;
}

void compareResult(T...)(Flag!"sortLines" sortLines, in T args) {
    static assert(args.length >= 1);

    foreach (a; args) {
        if (existsAsFile(a.gold)) {
            compare(a.gold, a.result, sortLines);
        }
    }
}

void compileResult(in Path input, in Path main, const ref TestEnv testEnv,
        Flag!"sortLines" sortLines, in string[] flags, in string[] incls) {
    auto binout = testEnv.outdir ~ "binary";

    Args args;
    args ~= "g++";
    args ~= flags.dup;
    args ~= "-g";
    args ~= "-o" ~ binout.escapePath;
    args ~= "-I" ~ testEnv.outdir.escapePath;
    args ~= incls.dup;
    args ~= input;
    args ~= main;

    runAndLog(args.data);
    runAndLog(binout.escapePath);
}

void demangleProfileLog(in Path out_fname) {
    Args args;
    args ~= "ddemangle";
    args ~= "trace.log";
    args ~= ">";
    args ~= out_fname.escapePath;

    runAndLog(args.data);
}

string[] compilerFlags() {
    auto default_flags = ["-std=c++98"];

    auto r = tryRunCollect("g++ -dumpversion");
    auto version_ = r.output;
    yap("Compiler version: ", version_);

    if (r.status != 0) {
        return default_flags;
    }

    if (version_.length == 0) {
        return default_flags;
    } else if (version_[0] == '5') {
        return default_flags ~ ["-Wpedantic", "-Werror"];
    } else {
        return default_flags ~ ["-pedantic", "-Werror"];
    }
}

string testId(uint line = __LINE__) {
    import std.conv : to;

    // assuming it is always the UDA for a test and thus +1 to get the correct line
    return "id:" ~ (line + 1).to!string() ~ " ";
}
