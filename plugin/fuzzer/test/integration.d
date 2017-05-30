/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool_test.integration;

import scriptlike;
import unit_threaded : shouldEqual;

import dextool_test.utils;

enum globalTestdir = "fuzzer_tests";

struct Compile {
    enum Kind {
        main,
        fuzzTest,
        original,
    }

    Kind kind;
    Path payload;
    alias payload this;
}

struct TestParams {
    bool doCompare = true;
    bool doCompile = true;

    Path root;
    Path testRoot;

    Path input;
    Path input_impl;
    Path[2][] output;

    Compile[] compileFiles;

    // dextool parameters;
    string[] dexParams;
    string[] dexFlags;

    // Compiler
    string[] compileFlags;
    string[] compileIncls;
    string originalCompilerVar;
}

TestParams genTestParams(string hdr, string impl, const ref TestEnv testEnv) {
    TestParams p;

    p.root = Path("plugin_testdata").absolutePath;
    p.input = p.root ~ Path(hdr);
    p.input_impl = p.root ~ Path(impl);
    p.testRoot = p.input.dirName;

    p.output ~= [p.input ~ Ext(".hpp.ref"), testEnv.outdir ~ "dextool_default_scheduler.hpp"];

    p.compileFiles ~= Compile(Compile.Kind.main, testEnv.outdir ~ "main.cpp");
    p.compileFiles ~= Compile(Compile.Kind.original, p.input_impl);

    p.dexParams = ["fuzzer", "--debug"];
    p.dexFlags = [];

    p.compileFlags = compilerFlags();
    p.compileIncls = ["-I" ~ p.input.dirName.toString];

    if (p.input_impl.extension == ".c") {
        p.originalCompilerVar = "CC";
    } else {
        p.originalCompilerVar = "CXX";
    }

    return p;
}

void runTestFile(ref TestParams p, ref TestEnv testEnv, Flag!"sortLines" sortLines = No.sortLines,
        Flag!"skipComments" skipComments = Yes.skipComments) {
    dextoolYap("Input:%s", p.input.raw);
    runDextool(p.input, testEnv, p.dexParams, p.dexFlags);

    if (p.doCompare) {
        dextoolYap("Comparing");
        auto input = p.input.stripExtension;
        foreach (o; p.output) {
            compareResult(sortLines, skipComments, GR(o[0], o[1]));
        }
    }

    if (p.doCompile) {
        dextoolYap("Compiling");

        // these only exist AFTER dextool has executed.
        auto comp_files = p.compileFiles ~ dirEntries(testEnv.outdir, "dextool_fuzz_case*.cpp",
                SpanMode.shallow).map!(a => Compile(Compile.Kind.fuzzTest, Path(a))).array();
        dextoolYap("Found generated fuzz tests: %s", comp_files);

        compile(testEnv.outdir ~ "binary", comp_files, p.compileFlags,
                p.compileIncls, p.originalCompilerVar, testEnv);
    }
}

void compile(const Path dst_binary, Compile[] files, const string[] flags,
        const string[] incls, string original_var, const ref TestEnv testEnv) {
    import core.sys.posix.sys.stat;
    import std.file : setAttributes;

    immutable bool[string] rm_flag = ["-Wpedantic" : true, "-Werror" : true, "-pedantic" : true];

    auto flags_ = flags.filter!(a => a !in rm_flag).array();

    Args compile_args;
    compile_args ~= "-g";
    compile_args ~= "-I" ~ testEnv.outdir.escapePath;
    compile_args ~= "-I" ~ "support";
    compile_args ~= incls.dup;

    Args wrapper_args;
    wrapper_args ~= flags_.dup;
    wrapper_args ~= "-o$OUT";
    wrapper_args ~= files.filter!(a => a.kind != Compile.Kind.original)
        .map!(a => a.payload).array().dup;
    wrapper_args ~= (testEnv.outdir ~ "original.o").toString;
    wrapper_args ~= "-l" ~ "dextoolfuzz";
    wrapper_args ~= "-L.";

    Args original_args;
    original_args ~= "-c";
    original_args ~= "-o" ~ (testEnv.outdir ~ "original.o").toString;
    original_args ~= files.filter!(a => a.kind == Compile.Kind.original)
        .map!(a => a.payload).array().dup;

    string script_p = (testEnv.outdir ~ "build.sh").toString;
    auto script = File(script_p, "w");
    script.writeln("#!/bin/bash");
    script.writeln("if [[ -z $CC ]]; then CC=gcc; fi");
    script.writeln("if [[ -z $CXX ]]; then CXX=g++; fi");
    script.writeln("if [[ -z $OUT ]]; then OUT=" ~ dst_binary.escapePath ~ "; fi");
    script.writefln("$%s $FLAGS %s %s", original_var, compile_args.data, original_args.data);
    script.writefln("$CXX $WRAPFLAGS %s %s", compile_args.data, wrapper_args.data);
    script.close();

    auto script_attr = getAttributes(script_p);
    script_attr = script_attr | S_IRWXU;
    setAttributes(script_p, script_attr);

    runAndLog(script_p).status.shouldEqual(0);
}

@(testId ~ "shall be a fuzzer environment for a void function")
unittest {
    mixin(envSetup(globalTestdir));

    auto p = genTestParams("stage_1/a_void_func.h", "stage_1/a_void_func.c", testEnv);
    p.doCompare = false;
    runTestFile(p, testEnv);
}

@(testId ~ "shall be a fuzzer environment for a function with parameters of primitive data types")
unittest {
    mixin(envSetup(globalTestdir));

    auto p = genTestParams("stage_1/func_with_primitive_params.h",
            "stage_1/func_with_primitive_params.c", testEnv);
    p.doCompare = false;
    runTestFile(p, testEnv);
}

@(testId ~ "shall be a fuzzer environment for a function with int params and lots of if-stmt")
unittest {
    mixin(envSetup(globalTestdir));

    auto p = genTestParams("stage_2/int_param_nested_if.hpp",
            "stage_2/int_param_nested_if.cpp", testEnv);
    p.doCompare = false;
    runTestFile(p, testEnv);
}

@(testId ~ "shall be a fuzzer environment with limits from a config file")
unittest {
    mixin(envSetup(globalTestdir));

    auto p = genTestParams("stage_2/limit_params.hpp", "stage_2/limit_params.cpp", testEnv);
    p.dexParams ~= "--config=" ~ (p.root ~ "stage_2/limit_params.xml").toString;
    p.doCompare = false;
    runTestFile(p, testEnv);
}

@(testId ~ "shall be a fuzzer environment with complex structs and transforms from a config file ")
unittest {
    mixin(envSetup(globalTestdir));

    auto p = genTestParams("stage_2/transform_param.hpp", "stage_2/transform_param.cpp", testEnv);
    p.dexParams ~= "--config=" ~ (p.root ~ "stage_2/transform_param.xml").toString;
    runTestFile(p, testEnv);
}

@(testId ~ "shall be a fuzzer environment fuzzing in a limited range following a config")
unittest {
    mixin(envSetup(globalTestdir));

    auto p = genTestParams("stage_2/user_param_fuzzer.hpp",
            "stage_2/user_param_fuzzer.cpp", testEnv);
    p.dexParams ~= "--config=" ~ (p.root ~ "stage_2/user_param_fuzzer.xml").toString;
    p.doCompare = false;
    runTestFile(p, testEnv);
}

@("shall be a working, complete test of the helper library")
unittest {
    mixin(envSetup(globalTestdir));

    auto p = genTestParams("", "test_lib/dummy.cpp", testEnv);
    // dfmt off
    auto comp_files =
        [Compile(Compile.Kind.main, p.root ~ Path("test_lib") ~ "main.cpp"),
        Compile(Compile.Kind.original, p.root ~ Path("test_lib") ~ "dummy.cpp")]
            ~
        ["test_fuzz_helper.cpp"]
        .map!(a => p.root ~ Path("test_lib") ~ a)
        .map!(a => Compile(Compile.Kind.fuzzTest, a))
        .array();
    // dfmt on

    compile(testEnv.outdir ~ "binary", comp_files, p.compileFlags,
            p.compileIncls, p.originalCompilerVar, testEnv);

    Args test;
    test ~= (testEnv.outdir ~ "binary").toString;
    test ~= (p.root ~ Path("test_lib") ~ "raw_dummy_data.cpp").toString;

    runAndLog(test).status.shouldEqual(0);
}
