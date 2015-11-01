// Written in the D programming language.
/**
Date: 2015, Joakim Brännström
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
 */
import scriptlike;
import std.path : asAbsolutePath, asNormalizedPath;

string OUTDIR = "outdata";
string DEXTOOL;

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

    run(args.data);
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

void stage1() {
    writeln("Stage 1");

    auto root = Path("testdata/cstub/stage_1");
    auto files = dirEntries(root, "*.{h,hpp}", SpanMode.shallow);

    foreach (f; files) {
        auto input_ext = Path(f);
        auto out_hdr = Path(.OUTDIR ~ "/test_double.hpp");
        auto out_impl = Path(.OUTDIR ~ "/test_double.cpp");
        auto out_global = Path(.OUTDIR ~ "/test_double_global.cpp");
        auto out_gmock = Path(.OUTDIR ~ "/test_double_gmock.hpp");

        print(Color.yellow, "[ Run ] ", input_ext);
        auto params = ["--debug"];
        switch (input_ext.baseName.toString) {
        case "class_func.hpp":
            runDextool(input_ext, params, ["-xc++", "-DAND_A_DEFINE"]);
            break;
        case "param_main.h":
            runDextool(input_ext, params ~ ["--main=Stub"], []);
            out_hdr = out_hdr.up ~ "stub.hpp";
            out_impl = out_impl.up ~ "stub.cpp";
            break;
        case "test_include_stdlib.hpp":
            runDextool(input_ext, params, ["-nostdinc"]);
            break;
        case "param_gmock.h":
            runDextool(input_ext, params ~ ["--gmock"], ["-nostdinc"]);
            break;

        default:
            runDextool(input_ext, params, []);
        }

        print(Color.yellow, "Comparing");
        auto input = input_ext.stripExtension;
        compareResult(GR(input ~ Ext(".hpp.ref"), out_hdr),
            GR(input ~ Ext(".cpp.ref"), out_impl),
            GR(Path(input.toString ~ "_global.cpp.ref"), out_global),
            GR(Path(input.toString ~ "_gmock.hpp.ref"), out_gmock));

        print(Color.yellow, "Compiling");
        auto flags = ["-std=c++03", "-Wpedantic", "-Werror"];
        auto incls = ["-I" ~ input_ext.dirName.toString];
        auto mainf = Path("main1.cpp");
        switch (input_ext.baseName.toString) {
        case "param_gmock.h":
            compileResult(out_impl, mainf, flags ~ ["-DTEST_INCLUDE", "-DTEST_FUNC_PTR"],
                incls);
            break;
        case "param_main.h":
            compileResult(out_impl, mainf, flags, incls);
            break;
        case "variables.h":
            compileResult(out_impl, mainf, flags, incls);
            break;
        case "const.h":
            compileResult(out_impl, mainf, flags ~ ["-DTEST_INCLUDE", "-DTEST_CONST"],
                incls);
            break;
        case "function_pointers.h":
            compileResult(out_impl, mainf, flags ~ ["-DTEST_INCLUDE", "-DTEST_FUNC_PTR"],
                incls);
            break;
        case "arrays.h":
            compileResult(out_impl, mainf, flags ~ ["-DTEST_INCLUDE", "-DTEST_ARRAY"],
                incls);
            break;

        default:
            compileResult(out_impl, mainf, flags ~ ["-DTEST_INCLUDE"], incls);
        }

        print(Color.green, "[  OK ] ", input_ext);
        cleanTestEnv();
    }
}

void stage2() {
    writeln("Stage 2");
}

int main(string[] args) {
    if (args.length <= 1) {
        writef("Usage: %s <path-to-dextool>\n", args[0]);
        return 1;
    }

    .OUTDIR = asNormalizedPath(asAbsolutePath(OUTDIR)).text;
    .DEXTOOL = asNormalizedPath(asAbsolutePath(args[1])).text;
    writeln("deXTool:\t", DEXTOOL);
    writeln("tmp:\t\t", OUTDIR);

    // Setup and cleanup
    chdir(thisExePath.dirName);
    scope (exit)
        teardownTestEnv();
    setupTestEnv();

    // start testing
    try {
        stage1();
        stage2();
    }
    catch (ErrorLevelException ex) {
        print(Color.red, ex.msg);
        pause();
        return 1;
    }

    return 0;
}
