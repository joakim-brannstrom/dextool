/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.integration;

import logger = std.experimental.logger;
import std.algorithm : map, filter;
import std.array : array;
import std.file : dirEntries, SpanMode, getAttributes;
import std.path : stripExtension, dirName, setExtension, extension;
import std.process : escapeShellFileName;
import std.range : chain, only;
import std.stdio : File;
import std.typecons : Flag, Yes, No;

import unit_threaded : shouldEqual;

import dextool_test;

enum globalTestdir = "fuzzer_tests";

void compile(T)(const ref TestEnv testEnv, T files, string[] includes) {
    foreach (const f; files) {
        const compiler = () {
            if (f.toString.extension == ".c")
                return "gcc";
            return "g++";
        }();
        makeCompile(testEnv, compiler).addArg("-c").addArg(f).addArg([
                "-o", (testEnv.outdir ~ f.baseName.setExtension(".o")).toString
                ]).addInclude(includes).run;
    }

    makeCompile(testEnv, "g++").outputToDefaultBinary.addFilesFromOutdirWithExtension(".o").run;
    makeCommand(testEnv, (testEnv.outdir ~ defaultBinary).toString);
}

@(testId ~ "shall be a fuzzer environment for a void function")
unittest {
    mixin(envSetup(globalTestdir));
    makeDextool(testEnv).addInputArg(testData ~ "stage_1/a_void_func.h").run;
    compile(testEnv, chain(recursiveFilesWithExtension(testEnv.outdir, ".cpp"),
            only(testData ~ "stage_1/a_void_func.c")), [
            (testData ~ "stage_1").toString
            ]);
}

@(testId ~ "shall be a fuzzer environment for a function with parameters of primitive data types")
unittest {
    mixin(envSetup(globalTestdir));
    makeDextool(testEnv).addInputArg(testData ~ "stage_1/func_with_primitive_params.h").run;
    compile(testEnv, chain(recursiveFilesWithExtension(testEnv.outdir, ".cpp"),
            only(testData ~ "stage_1/func_with_primitive_params.c")),
            [(testData ~ "stage_1").toString]);
}

@(testId ~ "shall be a fuzzer environment for a function with int params and lots of if-stmt")
unittest {
    mixin(envSetup(globalTestdir));
    makeDextool(testEnv).addInputArg(testData ~ "stage_2/int_param_nested_if.hpp").run;
    compile(testEnv, chain(recursiveFilesWithExtension(testEnv.outdir, ".cpp"),
            only(testData ~ "stage_2/int_param_nested_if.cpp")), [
            (testData ~ "stage_2").toString
            ]);
}

@(testId ~ "shall be a fuzzer environment with limits from a config file")
unittest {
    mixin(envSetup(globalTestdir));
    makeDextool(testEnv).addInputArg(testData ~ "stage_2/limit_params.hpp").run;
    compile(testEnv, chain(recursiveFilesWithExtension(testEnv.outdir, ".cpp"),
            only(testData ~ "stage_2/limit_params.cpp")), [
            (testData ~ "stage_2").toString
            ]);
}

@(testId ~ "shall be a fuzzer environment with complex structs and transforms from a config file ")
unittest {
    mixin(envSetup(globalTestdir));
    makeDextool(testEnv).addInputArg(testData ~ "stage_2/transform_param.hpp")
        .addArg(["--config", (testData ~ "stage_2/transform_param.xml").toString]).run;
    compile(testEnv, chain(recursiveFilesWithExtension(testEnv.outdir, ".cpp"),
            only(testData ~ "stage_2/transform_param.cpp")), [
            (testData ~ "stage_2").toString
            ]);
}

@(testId ~ "shall be a fuzzer environment fuzzing in a limited range following a config")
unittest {
    mixin(envSetup(globalTestdir));
    makeDextool(testEnv).addInputArg(testData ~ "stage_2/user_param_fuzzer.hpp")
        .addArg([
                "--config", (testData ~ "stage_2/user_param_fuzzer.xml").toString
                ]).run;
    compile(testEnv, chain(recursiveFilesWithExtension(testEnv.outdir, ".cpp"),
            only(testData ~ "stage_2/user_param_fuzzer.cpp")), [
            (testData ~ "stage_2").toString
            ]);
}

@("shall be a working, complete test of the helper library")
unittest {
    mixin(envSetup(globalTestdir));

    // dfmt off
    makeCompile(testEnv, "g++")
        .outputToDefaultBinary
        .addArg("-std=c++98")
        .addInclude("support")
        .addInclude("test_lib")
        .addArg(testData ~ "test_lib/main.cpp")
        .addArg(testData ~ "test_lib/dummy.cpp")
        .addArg(testData ~ "test_lib/test_fuzz_helper.cpp")
        .addArg(["-l", "dextoolfuzz"])
        .addArg("-L.")
        .run;
    makeCommand(testEnv, (testEnv.outdir ~ defaultBinary).toString);
    // dfmt on
}

auto makeDextool(const ref TestEnv env) {
    return dextool_test.makeDextool(env).setWorkdir(env.outdir).args(["fuzzer"]);
}

auto makeCompile(const ref TestEnv env, string compiler) {
    // dfmt off
    return dextool_test.makeCompile(env, compiler)
        .addInclude("support")
        .addPostArg(["-l", "dextoolfuzz"])
        .addPostArg(["-L", Path(".").toString]);
    // dfmt on
}

Path testData() {
    return Path("plugin_testdata");
}
