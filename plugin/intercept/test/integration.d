/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.integration;

import scriptlike;
import unit_threaded : shouldEqual;

import dextool_test.utils;

enum globalTestdir = "intercept_tests";

auto testData() {
    return Path("plugin_testdata").absolutePath;
}

auto makeDextool(const ref TestEnv env) {
    return dextool_test.utils.makeDextool(env).args(["intercept", "-d", "--prefix=i_"]);
}

auto verifyOutput(const ref TestEnv env, Path infile) {
    auto f = infile.stripExtension;
    compareResult(No.sortLines, Yes.skipComments, GR(f ~ Ext(".hpp.ref"),
            env.outdir ~ "intercept.hpp"), GR(f ~ Ext(".cpp.ref"), env.outdir ~ "intercept.cpp"));
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

    // prepare the static library
    {
        Args args;
        args ~= "gcc";
        args ~= ["-c"] ~ (testData ~ "stage_3/test_replace_single_sym/orig.c").toString;
        args ~= ["-o", (testEnv.outdir ~ "orig.o").toString];
        runAndLog(args.data).status.shouldEqual(0);
    }
    {
        Args args;
        args ~= ["ar", "-r", orig_lib, (testEnv.outdir ~ "orig.o").toString];
        runAndLog(args.data).status.shouldEqual(0);
    }

    // expect headers and script to replace the specified symbol
    makeDextool(testEnv).addInputArg(testData ~ "stage_3/test_replace_single_sym/orig.h")
        .addArg("--config=" ~ (testData ~ "stage_3/test_replace_single_sym/conf.xml").toString).run;

    { // use the generated script to generate the new lib with rename sym
        Args args;
        args ~= "bash";
        args ~= (testEnv.outdir ~ "intercept.sh").toString;
        args ~= orig_lib;
        args ~= replace_lib;
        runAndLog(args.data).status.shouldEqual(0);
    }

    string binary = (testEnv.outdir ~ "binary").toString;
    { // build the binary with the intercept lib
        Args args;
        args ~= "g++";
        args ~= (testData ~ "stage_3/test_replace_single_sym/main.cpp").toString;
        args ~= ["-o", binary];
        args ~= ["-I", (testData ~ "stage_3/test_replace_single_sym").toString];
        args ~= compilerFlags;
        args ~= ["-I", testEnv.outdir.toString];
        args ~= ["-lintercept_orig", "-L" ~ testEnv.outdir.toString];
        runAndLog(args.data).status.shouldEqual(0);
    }

    { // the modified lib shall result in the intercepted func incrementing the value
        runAndLog(binary).status.shouldEqual(0);
    }
}
