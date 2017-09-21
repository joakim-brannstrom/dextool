/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.utility;

import std.typecons : Flag, Yes, No;

public import scriptlike;
public import unit_threaded;

public import dextool_test;
public import dextool_test.config;

auto makeDextool(const ref TestEnv env) {
    return dextool_test.makeDextool(env).args(["ctestdouble", "-d"]);
}

auto makeCompile(const ref TestEnv env, Path srcdir) {
    return dextool_test.makeCompile(env, "g++").addInclude(srcdir)
        .addArg(testData ~ "main1.cpp").outputToDefaultBinary;
}

struct TestParams {
    Flag!"skipCompare" skipCompare;
    Flag!"skipCompile" skipCompile;
    bool useGTest;

    Path root;
    Path input_ext;

    Path base_cmp;
    Path out_hdr;
    Path out_impl;
    Path out_global;
    Path out_gmock;

    // dextool parameters;
    string[] dexParams;
    string[] dexFlags;

    // Compiler flags
    string[] compileFlags;
    string[] compileIncls;

    Path mainf;
    Path binary;
}

TestParams genTestParams(string f, const ref TestEnv testEnv) {
    TestParams p;

    p.root = Path("testdata/cstub").absolutePath;
    p.input_ext = p.root ~ Path(f);
    p.base_cmp = p.input_ext.stripExtension;

    p.out_hdr = testEnv.outdir ~ "test_double.hpp";
    p.out_impl = testEnv.outdir ~ "test_double.cpp";
    p.out_global = testEnv.outdir ~ "test_double_global.cpp";
    p.out_gmock = testEnv.outdir ~ "test_double_gmock.hpp";

    p.dexParams = ["--DRT-gcopt=profile:1", "ctestdouble", "--debug"];
    p.dexFlags = [];

    p.compileFlags = compilerFlags();
    p.compileIncls = ["-I" ~ p.input_ext.dirName.toString];

    p.mainf = p.root ~ Path("main1.cpp");
    p.binary = p.root ~ testEnv.outdir ~ "binary";

    return p;
}

TestParams genGtestParams(string base, const ref TestEnv testEnv) {
    auto env = genTestParams(base, testEnv);
    env.dexParams ~= "--gmock";
    env.useGTest = true;
    env.mainf = Path(env.input_ext.stripExtension.toString ~ "_test.cpp");

    return env;
}

void runTestFile(const ref TestParams p, ref TestEnv testEnv,
        Flag!"sortLines" sortLines = No.sortLines,
        Flag!"skipComments" skipComments = Yes.skipComments) {
    dextoolYap("Input:%s", p.input_ext.raw);
    runDextool(p.input_ext, testEnv, p.dexParams, p.dexFlags);

    if (p.useGTest) {
        dextoolYap("Google Test");
        testWithGTest([p.out_impl, p.mainf], p.binary, testEnv, p.compileFlags, p.compileIncls);
        runAndLog(p.binary).status.shouldEqual(0);
        return;
    }

    if (!p.skipCompare) {
        dextoolYap("Comparing");
        Path base = p.base_cmp;
        // dfmt off
        compareResult(sortLines, skipComments,
                      GR(base ~ Ext(".hpp.ref"), p.out_hdr),
                      GR(base ~ Ext(".cpp.ref"), p.out_impl),
                      GR(Path(base.toString ~ "_global.cpp.ref"), p.out_global),
                      GR(Path(base.toString ~ "_gmock.hpp.ref"), p.out_gmock));
        // dfmt on
    }

    if (!p.skipCompile) {
        dextoolYap("Compiling");
        compileResult(p.out_impl, p.binary, p.mainf, testEnv, p.compileFlags, p.compileIncls);
        runAndLog(p.binary).status.shouldEqual(0);
    }
}
