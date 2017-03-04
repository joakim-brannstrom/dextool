/**
Copyright: Copyright (c) 2015-2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
 */
module cpp_tests;

import scriptlike;
import utils;
import std.typecons : Flag, Yes, No;

import unit_threaded : Name, shouldEqual, ShouldFail;

enum globalTestdir = "cpp_tests";

struct TestParams {
    Flag!"skipCompare" skipCompare;
    Flag!"skipCompile" skipCompile;

    Path root;
    Path input_ext;
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

    p.root = Path("testdata/cpp").absolutePath;
    p.input_ext = p.root ~ Path(f);

    p.out_hdr = testEnv.outdir ~ "test_double.hpp";
    p.out_impl = testEnv.outdir ~ "test_double.cpp";
    p.out_global = testEnv.outdir ~ "test_double_global.cpp";
    p.out_gmock = testEnv.outdir ~ "test_double_gmock.hpp";

    p.dexParams = ["--DRT-gcopt=profile:1", "cpptestdouble", "--debug", "--gmock"];
    p.dexFlags = [];

    p.compileFlags = compilerFlags();
    p.compileIncls = ["-I" ~ p.input_ext.dirName.toString];

    p.mainf = p.root ~ Path("main_dev.cpp");
    p.binary = p.root ~ testEnv.outdir ~ "binary";

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
                      GR(Path(input.toString ~ "_global.cpp.ref"), p.out_global),
                      GR(Path(input.toString ~ "_gmock.hpp.ref"), p.out_gmock));
        // dfmt on
    }

    if (!p.skipCompile) {
        dextoolYap("Compiling");
        compileResult(p.out_impl, p.binary, p.mainf, testEnv, p.compileFlags, p.compileIncls);
        runAndLog(p.binary).status.shouldEqual(0);
    }
}

// --- Development tests ---

@Name(testId ~ "Should not segfault. Bug with anonymous namespace")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/bug_anon_namespace.hpp", testEnv);

    dextoolYap("Input:%s", p.input_ext.raw);
    runTestFile(p, testEnv);
}

@Name(testId ~ "Should not segfault or infinite recursion when poking at unexposed")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/bug_unexposed.hpp", testEnv);
    p.compileFlags ~= ["-DTEST_INCLUDE"];
    runTestFile(p, testEnv);
}

@Name(testId
        ~ "Should detect the type even though it is wchar_t. Bug: was treated specially which resulted in it never being set")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/bug_wchar.hpp", testEnv);
    p.compileFlags ~= ["-DTEST_INCLUDE"];
    runTestFile(p, testEnv);
}

@Name(testId ~ "Should be a google mock with a constant member method")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/class_const.hpp", testEnv);
    p.compileFlags ~= ["-DTEST_INCLUDE"];
    runTestFile(p, testEnv);
}

@Name(testId ~ "Should be gmocks that correctly implemented classes that inherit")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/class_inherit.hpp", testEnv);
    p.compileFlags ~= ["-DTEST_INCLUDE"];
    runTestFile(p, testEnv);
}

@Name(testId ~ "Should be gmock with member methods and operators")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/class_interface.hpp", testEnv);
    p.compileFlags ~= ["-DTEST_INCLUDE"];
    runTestFile(p, testEnv);
}

@Name(testId ~ "Should be a gmock with more than 10 parameters")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/class_interface_more_than_10_params.hpp", testEnv);
    p.compileFlags ~= ["-DTEST_INCLUDE"];
    runTestFile(p, testEnv);
}

@Name(testId ~ "Should be a gmock impl for each class")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/class_multiple.hpp", testEnv);
    p.compileFlags ~= ["-DTEST_INCLUDE"];
    runTestFile(p, testEnv);
}

@Name(testId ~ "Test common class patterns and there generated gmocks. See input file for info")
unittest {
    //TODO split input in many tests.

    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/class_variants_interface.hpp", testEnv);
    p.compileFlags ~= ["-DTEST_INCLUDE"];
    runTestFile(p, testEnv);
}

@Name(testId ~ "Should exclude self from generated test double")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/exclude_self.hpp", testEnv);
    p.dexParams ~= ["--file-exclude=.*/" ~ p.input_ext.baseName.toString];
    p.compileFlags ~= ["-DTEST_INCLUDE"];
    p.compileIncls ~= "-I" ~ (p.root ~ "dev/extra").toString;

    p.dexFlags = p.compileIncls;

    runTestFile(p, testEnv);
}

@Name(testId ~ "Should generate implementation of functions in ns and externs")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/extern_in_ns.hpp", testEnv);
    p.compileFlags ~= ["-DTEST_INCLUDE"];
    p.compileIncls ~= "-I" ~ (p.root ~ "dev/extra").toString;

    p.dexFlags = p.compileIncls;

    runTestFile(p, testEnv);
}

@Name(testId ~ "Should only generate impl for those functions in ns")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/functions_in_ns.hpp", testEnv);
    p.compileFlags ~= ["-DTEST_INCLUDE"];
    runTestFile(p, testEnv);
}

@Name(testId ~ "Should use root as include")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/have_root.hpp", testEnv);
    p.compileFlags ~= ["-DTEST_INCLUDE"];
    p.compileIncls ~= "-I" ~ (p.root ~ "dev/extra").toString;

    p.dexFlags = p.compileIncls;

    runTestFile(p, testEnv);
}

@Name(testId ~ "Test --file-restrict")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/param_restrict.hpp", testEnv);
    p.dexParams ~= ["--file-restrict=.*/" ~ p.input_ext.baseName.toString,
        "--file-restrict=.*/b.hpp"];
    p.compileFlags ~= ["-DTEST_INCLUDE"];
    p.compileIncls ~= "-I" ~ (p.root ~ "dev/extra").toString;

    p.dexFlags = p.compileIncls;

    runTestFile(p, testEnv);
}

@Name(testId ~ "Should load compiler settings from compilation database")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("compile_db/single_file_main.hpp", testEnv);

    // find compilation flags by looking up how single_file_main.c was compiled
    p.dexParams ~= ["--compile-db=" ~ (p.root ~ "compile_db/single_file_db.json")
        .toString, "--file-restrict=.*/single_file.hpp"];

    p.compileIncls ~= "-I" ~ (p.root ~ "compile_db/dir1").toString;
    p.compileFlags ~= "-DDEXTOOL_TEST";

    p.mainf = p.root ~ Path("compile_db/single_file_main.cpp");
    runTestFile(p, testEnv);
}

@Name(testId ~ "Should not crash when std::system_error isn't found during analyze")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/bug_class_not_in_ast.hpp", testEnv);
    p.skipCompile = Yes.skipCompile;
    runTestFile(p, testEnv);
}

@Name(testId ~ "Should be a gmock of the class that is NOT forward declared")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/class_forward_decl.hpp", testEnv);
    p.skipCompile = Yes.skipCompile;
    runTestFile(p, testEnv);
}

// BEGIN CLI Tests ###########################################################

@Name(testId ~ "Should be a custom header via CLI as string")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/param_custom_header.hpp", testEnv);
    p.dexParams ~= ["--header=// user $file$\n// header $file$"];

    p.skipCompile = Yes.skipCompile;
    runTestFile(p, testEnv, No.sortLines, No.skipComments);
}

@Name(testId ~ "Should be a custom header via CLI as filename")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/param_custom_header.hpp", testEnv);
    p.dexParams ~= ["--header-file=" ~ (p.root ~ "dev/param_custom_header.txt").toString];

    p.skipCompile = Yes.skipCompile;
    runTestFile(p, testEnv, No.sortLines, No.skipComments);
}

@(testId ~ "Configuration data read from a file")
unittest {
    mixin(envSetup(globalTestdir));

    auto p = genTestParams("stage_2/config.hpp", testEnv);
    p.dexParams ~= ["--config", (p.root ~ "stage_2/config.xml").toString,
        "--compile-db=" ~ (p.root ~ "stage_2/config.json").toString];
    p.compileFlags = ["-DTEST_INCLUDE"];

    p.skipCompare = Yes.skipCompare;

    runTestFile(p, testEnv);
}

// END   CLI Tests ###########################################################
