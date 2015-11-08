// Written in the D programming language.
/**
Date: 2015, Joakim Brännström
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
 */
module utils;
import scriptlike;
import std.path : asAbsolutePath, asNormalizedPath;

string OUTDIR = "outdata";
string DEXTOOL = "dextool";

void setOutdir(string p) {
    .OUTDIR = asNormalizedPath(asAbsolutePath(OUTDIR)).text;
    writeln("tmp:\t\t", OUTDIR);
}

void setDextool(string p) {
    .DEXTOOL = asNormalizedPath(asAbsolutePath(p)).text;
    writeln("deXTool:\t", DEXTOOL);
}

enum Color {
    red,
    green,
    yellow,
    cancel
}

struct GR {
    Path gold;
    Path result;
}

void print(T...)(Color c, T args) {
    immutable string[] escCodes = ["\033[31;1m", "\033[32;1m", "\033[33;1m", "\033[0;;m"];

    writeln(escCodes[c], args, escCodes[Color.cancel]);
}

void setupTestEnv() {
    mkdirRecurse(OUTDIR);
}

void cleanTestEnv() {
    auto range = dirEntries(OUTDIR, SpanMode.shallow);
    range.each!(a => tryRemove(Path(a)));
}

void teardownTestEnv() {
    tryRmdirRecurse(OUTDIR);
}

void compare(Path gold, Path result) {
    Args args;
    args ~= "diff";
    args ~= "-u";
    args ~= gold;
    args ~= result;

    writef("Comparing result: %s\t%s\n", gold, result);
    run(args.data);
}

void runDextool(Path input, string[] pre_args, string[] flags) {
    .scriptlikeEcho = true;
    scope (exit)
        .scriptlikeEcho = false;

    Args args;
    args ~= .DEXTOOL;
    args ~= "ctestdouble";
    args ~= pre_args;
    args ~= "--out=" ~ .OUTDIR;
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
    print(Color.yellow, "time in ms: " ~ sw.peek().msecs.text);
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

    auto binout = Path(OUTDIR ~ "/binary");

    Args args;
    args ~= "g++";
    args ~= flags;
    args ~= "-g";
    args ~= "-o" ~ binout.toString;
    args ~= "-I" ~ .OUTDIR;
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
