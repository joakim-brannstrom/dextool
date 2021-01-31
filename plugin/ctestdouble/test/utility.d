/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.utility;

import std.typecons : Flag, Yes, No;
import std.path : stripExtension, dirName, setExtension;
public import logger = std.experimental.logger;

public import unit_threaded;

public import dextool_test.config;
public import dextool_test.types;
public import dextool_test;

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

    p.root = Path("testdata/cstub");
    p.input_ext = p.root ~ f;
    p.base_cmp = p.input_ext.toString.stripExtension.Path;

    p.out_hdr = testEnv.outdir ~ "test_double.hpp";
    p.out_impl = testEnv.outdir ~ "test_double.cpp";
    p.out_global = testEnv.outdir ~ "test_double_global.cpp";
    p.out_gmock = testEnv.outdir ~ "test_double_gmock.hpp";

    p.dexParams = ["--DRT-gcopt=profile:1", "ctestdouble", "--debug"];
    p.dexFlags = [];

    p.compileFlags = compilerFlags();
    p.compileIncls = ["-I" ~ p.input_ext.dirName.toString];

    p.mainf = p.root ~ "main1.cpp";
    p.binary = testEnv.outdir ~ "binary";

    return p;
}

TestParams genGtestParams(string base, const ref TestEnv testEnv) {
    auto env = genTestParams(base, testEnv);
    env.dexParams ~= "--gmock";
    env.useGTest = true;
    env.mainf = (env.input_ext.toString.stripExtension ~ "_test.cpp").Path;

    return env;
}

void runTestFile(const ref TestParams p, ref TestEnv testEnv,
        Flag!"sortLines" sortLines = No.sortLines,
        Flag!"skipComments" skipComments = Yes.skipComments) {
    import std.process : execute;

    logger.info("Input:", p.input_ext);
    runDextool(p.input_ext, testEnv, p.dexParams, p.dexFlags);

    if (p.useGTest) {
        logger.info("Google Test");
        testWithGTest([p.out_impl, p.mainf], p.binary, testEnv, p.compileFlags, p.compileIncls);
        auto res = execute(p.binary.toString);
        logger.info(res.output);
        res.status.shouldEqual(0);
        return;
    }

    if (!p.skipCompare) {
        logger.info("Comparing");
        Path base = p.base_cmp;
        // dfmt off
        compareResult(sortLines, skipComments,
                      GR(base.toString.setExtension(".hpp.ref").Path, p.out_hdr),
                      GR(base.toString.setExtension(".cpp.ref").Path, p.out_impl),
                      GR(Path(base.toString ~ "_global.cpp.ref"), p.out_global),
                      GR(Path(base.toString ~ "_gmock.hpp.ref"), p.out_gmock));
        // dfmt on
    }

    if (!p.skipCompile) {
        logger.info("Compiling");
        compileResult(p.out_impl, p.binary, p.mainf, testEnv, p.compileFlags, p.compileIncls);
        auto res = execute(p.binary.toString);
        logger.info(res.output);
        res.status.shouldEqual(0);
    }
}

auto readXmlLog(const ref TestEnv testEnv) {
    import std.array : array;
    import std.file : readText;
    import std.string : splitLines;

    // dfmt off
    return readText((testEnv.outdir ~ xmlLog).toString)
        .splitLines
        .array();
    // dfmt on
}
