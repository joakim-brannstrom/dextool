/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.integration;

import scriptlike;
import unit_threaded : shouldEqual;

import dextool_test;

enum globalTestdir = "intercept_tests";

auto testData() {
    return Path("plugin_testdata").absolutePath;
}

auto makeDextool(const ref TestEnv env) {
    return dextool_test.makeDextool(env).args(["intercept", "-d", "--prefix=i_"]);
}

auto verifyOutput(const ref TestEnv env, Path infile) {
    auto f = infile.stripExtension;
    // dfmt off
    makeCompare(env)
        .addCompare(f ~ Ext(".hpp.ref"), "intercept.hpp")
        .addCompare(f ~ Ext(".cpp.ref"), "intercept.cpp")
        .run;
    // dfmt on
}

@(testId ~ "Shall intercept the functions")
unittest {
    mixin(envSetup(globalTestdir));

    makeDextool(testEnv).addInputArg(testData ~ "stage_1/function.h").run;
    verifyOutput(testEnv, testData ~ "stage_1/function.h");
}

// === Stage 3 ===

@(testId ~ "Shall intercept the function in the static library by using the objcopy script")
unittest {
    mixin(envSetup(globalTestdir));

    string orig_lib = (testEnv.outdir ~ "liborig.a").toString;
    string replace_lib = (testEnv.outdir ~ "libintercept_orig.a").toString;

    // dfmt off

    // prepare the static library
    makeCompile(testEnv, "gcc")
        .addArg("-c")
        .addArg((testData ~ "stage_3/test_replace_single_sym/orig.c").toString)
        .addArg("-o" ~ (testEnv.outdir ~ "orig.o").toString)
        .run;

    makeCommand("ar")
        .addArg("-r")
        .addArg(orig_lib)
        .addArg(testEnv.outdir ~ "orig.o")
        .run;

    // expect headers and script to replace the specified symbol
    makeDextool(testEnv)
        .addInputArg(testData ~ "stage_3/test_replace_single_sym/orig.h")
        .addArg("--config=" ~ (testData ~ "stage_3/test_replace_single_sym/conf.xml").toString)
        .run;

    // use the generated script to generate the new lib with rename sym
    makeCommand("bash")
        .addArg(testEnv.outdir ~ "intercept.sh")
        .addArg(orig_lib)
        .addArg(replace_lib)
        .run;

    makeCompile(testEnv, "g++")
        .addArg(testData ~ "stage_3/test_replace_single_sym/main.cpp")
        .outputToDefaultBinary
        .addArg("-I" ~ (testData ~ "stage_3/test_replace_single_sym").toString)
        .addArg(compilerFlags)
        .addArg("-lintercept_orig")
        .addArg("-L" ~ testEnv.outdir.toString)
        .run;

    // the modified lib shall result in the intercepted func incrementing the value
    makeCommand(testEnv, (testEnv.outdir ~ "binary").toString);

    // dfmt on
}
