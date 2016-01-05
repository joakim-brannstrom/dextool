// Written in the D programming language.
/**
Date: 2015, Joakim Brännström
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
 */
module utils;
import scriptlike;
import std.path : asAbsolutePath, asNormalizedPath;

struct TestEnv {
    Path outdir;
    Path logdir;
    Path dextool;

    this(string outdir, string logdir, string dextool) {
        this.outdir = Path(outdir).absolutePath;
        this.logdir = Path(logdir).absolutePath;
        this.dextool = Path(dextool);
    }

    string toString() {
        // dfmt off
        return only(
                    ["dextool:", dextool.toString],
                    ["tmp:", outdir.toString],
                    ["logdir:", logdir.toString])
            .map!(a => leftJustifier(a[0], 10).text ~ a[1])
            .joiner("\n")
            .text;
        // dfmt on
    }

    void setup() {
        writeln("Test environment:\n", toString);

        mkdirRecurse(outdir);

        // ensure logs are empty
        if (exists(logdir)) {
            dirEntries(logdir, SpanMode.shallow).each!(a => tryRmdirRecurse(Path(a)));
        }
    }

    void clean() {
        auto range = dirEntries(outdir, SpanMode.shallow);
        range.each!(a => tryRemove(Path(a)));
    }

    void teardown() {
        tryRmdirRecurse(outdir);
    }

    void writeLog(string logname, string msg) {
        mkdirRecurse(logdir);

        auto f = File((logdir ~ logname ~ Ext(".txt")).toString, "w");
        f.write(msg);
    }

    /// Use when saving error data for later analyze
    void save(string name) {
        auto dst = logdir ~ name;
        mkdirRecurse(dst);

        Args a;
        a ~= "cp";
        a ~= "-r";
        a ~= outdir.toString ~ "/*";
        a ~= dst;
        run(a.data);
    }
}

Nullable!TestEnv testEnv;

enum Color {
    red,
    green,
    yellow,
    cancel
}

enum Status {
    Fail,
    Warn,
    Ok,
    Run
}

struct GR {
    Path gold;
    Path result;
}

void print(T...)(Color c, T args) {
    static immutable string[] escCodes = ["\033[31;1m", "\033[32;1m", "\033[33;1m",
        "\033[0;;m"];
    write(escCodes[c], args, escCodes[Color.cancel]);
}

void println(T...)(Color c, T args) {
    static immutable string[] escCodes = ["\033[31;1m", "\033[32;1m", "\033[33;1m",
        "\033[0;;m"];
    writeln(escCodes[c], args, escCodes[Color.cancel]);
}

void printStatus(T...)(Status s, T args) {
    Color c;
    string txt;

    final switch (s) {
    case Status.Ok:
        c = Color.green;
        txt = "[  OK ] ";
        break;
    case Status.Run:
        c = Color.yellow;
        txt = "[ RUN ] ";
        break;
    case Status.Fail:
        c = Color.red;
        txt = "[ FAIL] ";
        break;
    case Status.Warn:
        c = Color.red;
        txt = "[ WARN] ";
        break;
    }

    print(c, txt);
    writeln(args);
}

void compare(Path gold, Path result) {
    import std.stdio : File;

    writef("Comparing gold:'%s'\t output:'%s'\n", gold, result);

    File goldf;
    File resultf;

    try {
        goldf = File(gold.toString);
        resultf = File(result.toString);
    }
    catch (ErrnoException ex) {
        throw new ErrorLevelException(-1, ex.msg);
    }

    bool diff_detected = false;
    int max_diff;
    foreach (idx, g, r; lockstep(goldf.byLine(), resultf.byLine())) {
        if (g.length > 2 && r.length > 2 && g[0 .. 2] == "//" && r[0 .. 2] == "//") {
            continue;
        } else if (g != r && max_diff < 5) {
            // +1 of index because editors start counting lines from 1
            writef("Line %d\t\ngold: %s\nout:  %s\n", idx + 1, g, r);
            diff_detected = true;
            ++max_diff;
        }
    }

    if (diff_detected) {
        throw new ErrorLevelException(-1,
            "Output is different from reference file (gold): " ~ gold.toString);
    }
}

void runDextool(Path input, string[] pre_args, string[] flags) {
    .scriptlikeEcho = true;
    scope (exit)
        .scriptlikeEcho = false;

    Args args;
    args ~= testEnv.dextool;
    args ~= pre_args;
    args ~= "--out=" ~ testEnv.outdir.toString;
    args ~= input.toString;

    if (flags.length > 0) {
        args ~= "--";
        args ~= flags;
    }

    import std.datetime;

    StopWatch sw;
    sw.start;
    run(args.data);
    sw.stop;
    println(Color.yellow, "time in ms: " ~ sw.peek().msecs.text);
}

void compareResult(T...)(T args) {
    static assert(args.length >= 1);

    foreach (a; args) {
        if (existsAsFile(a.gold)) {
            compare(a.gold, a.result);
        }
    }
}

void compileResult(Path input, Path main, string[] flags, string[] incls) {
    .scriptlikeEcho = true;
    scope (exit)
        .scriptlikeEcho = false;

    auto binout = testEnv.outdir ~ "binary";

    Args args;
    args ~= "g++";
    args ~= flags;
    args ~= "-g";
    args ~= "-o" ~ binout.toString;
    args ~= "-I" ~ testEnv.outdir.toString;
    args ~= incls;
    args ~= input;
    args ~= main;

    run(args.data);
    run(binout.toString);
}

void demangleProfileLog(Path out_fname) {
    .scriptlikeEcho = true;
    scope (exit)
        .scriptlikeEcho = false;

    Args args;
    args ~= "ddemangle";
    args ~= "trace.log";
    args ~= ">";
    args ~= out_fname.toString;

    run(args.data);
}
