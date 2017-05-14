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

struct TestParams {
    Flag!"skipCompare" skipCompare;

    Path root;
    Path input_ext;
    Path out_hdr;
    Path out_impl;

    // dextool parameters;
    string[] dexParams;
    string[] dexFlags;

    // Compiler flags
    string[] compileFlags;
    string[] compileIncls;
}

TestParams genTestParams(string f, const ref TestEnv testEnv) {
    TestParams p;

    p.root = Path("plugin_testdata").absolutePath;
    p.input_ext = p.root ~ Path(f);

    p.out_hdr = testEnv.outdir ~ "intercept.hpp";
    p.out_impl = testEnv.outdir ~ "intercept.cpp";

    p.dexParams = ["--DRT-gcopt=profile:1", "intercept", "--debug", "--prefix=i_"];
    p.dexFlags = [];

    p.compileFlags = compilerFlags();
    p.compileIncls = ["-I" ~ p.input_ext.dirName.toString];

    return p;
}

void runTestFile(const ref TestParams p, ref TestEnv testEnv,
        Flag!"sortLines" sortLines = No.sortLines,
        Flag!"skipComments" skipComments = Yes.skipComments) {

    dextoolYap("Input:%s", p.input_ext.raw);
    runDextool(p.input_ext, testEnv, p.dexParams, p.dexFlags);

    if (!p.skipCompare) {
        dextoolYap("Comparing");
        auto input = p.input_ext.stripExtension;
        // dfmt off
        compareResult(sortLines, skipComments,
                      GR(input ~ Ext(".hpp.ref"), p.out_hdr),
                      GR(input ~ Ext(".cpp.ref"), p.out_impl),
                      );
        // dfmt on
    }
}

@(testId ~ "Shall intercept the functions")
unittest {
    mixin(envSetup(globalTestdir));

    auto p = genTestParams("stage_1/function.h", testEnv);
    runTestFile(p, testEnv);
}

// === Stage 3 ===

@(testId ~ "Shall intercept the function in the static library by using the objcopy script")
unittest {
    mixin(envSetup(globalTestdir));

    auto p = genTestParams("stage_3/test_replace_single_sym/orig.h", testEnv);
    p.dexParams ~= "--config=" ~ (p.root ~ "stage_3/test_replace_single_sym/conf.xml").toString;

    string orig_lib = (testEnv.outdir ~ "liborig.a").toString;
    string replace_lib = (testEnv.outdir ~ "libintercept_orig.a").toString;

    // prepare the static library
    {
        Args args;
        args ~= "gcc";
        args ~= p.compileIncls;
        args ~= ["-c"] ~ (p.root ~ "stage_3/test_replace_single_sym/orig.c").toString;
        args ~= ["-o", (testEnv.outdir ~ "orig.o").toString];
        runAndLog(args.data).status.shouldEqual(0);
    }
    {
        Args args;
        args ~= ["ar", "-r", orig_lib, (testEnv.outdir ~ "orig.o").toString];
        runAndLog(args.data).status.shouldEqual(0);
    }

    // expect headers and script to replace the specified symbol
    runTestFile(p, testEnv);

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
        args ~= (p.root ~ "stage_3/test_replace_single_sym/main.cpp").toString;
        args ~= ["-o", binary];
        args ~= p.compileIncls ~ p.compileFlags;
        args ~= ["-I", testEnv.outdir.toString];
        args ~= ["-lintercept_orig", "-L" ~ testEnv.outdir.toString];
        runAndLog(args.data).status.shouldEqual(0);
    }

    { // the modified lib shall result in the intercepted func incrementing the value
        runAndLog(binary).status.shouldEqual(0);
    }
}
