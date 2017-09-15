/**
Copyright: Copyright (c) 2015-2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
 */
module dextool_test.integration;

import std.typecons : Flag, Yes, No;

import scriptlike;
import dextool_test;

import unit_threaded;

enum globalTestdir = "c_tests";

auto testData() {
    return Path("testdata/cstub").absolutePath;
}

auto makeDextool(const ref TestEnv env) {
    return dextool_test.makeDextool(env).args(["ctestdouble", "-d"]);
}

auto makeCompile(const ref TestEnv env, Path srcdir) {
    return dextool_test.makeCompile(env, "g++").addArg(["-I", srcdir.toString])
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

// dfmt makes it hard to read the test cases.
// dfmt off

// --- Stage 1 ---
@(testId ~ "Should detect as func")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_1/bug_func_attr.h", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should detect as func and not as param when parsed as C")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_1/bug_typedef_func.h", testEnv);
    runTestFile(p, testEnv);
}

@(testId ~ "Should be correct declarations of arrays")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_1/arrays.h", testEnv);
    p.compileFlags ~= ["-DTEST_ARRAY", "-DTEST_INCLUDE"];
    runTestFile(p, testEnv);
}

@(testId ~ "Should ignore C++ code")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_1/class_func.hpp", testEnv);
    p.dexFlags = ["-xc++", "-DAND_A_DEFINE"];
    p.compileFlags ~= "-DTEST_INCLUDE";
    runTestFile(p, testEnv);
}

@(testId ~ "Should be global constants with defines to allow initialization")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_1/const.h", testEnv);
    p.compileFlags ~= ["-DTEST_CONST", "-DTEST_INCLUDE"];
    runTestFile(p, testEnv);
}

@(testId ~ "Should be plain function pointers or implementations")
unittest {
    //TODO split the test in two, "global func pointers"/"use typedef func prototype for declaration"
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_1/function_pointers.h", testEnv);
    p.compileFlags ~= ["-DTEST_FUNC_PTR", "-DTEST_INCLUDE"];
    runTestFile(p, testEnv);
}

@(testId ~ "Should be implementations of C functions")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_1/functions.h", testEnv);
    p.compileFlags ~= ["-DTEST_INCLUDE", "-DTEST_FUNC"];
    runTestFile(p, testEnv);
}

@(testId ~ "Should ignore the structs")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_1/structs.h", testEnv);
    p.skipCompile = Yes.skipCompile;
    runTestFile(p, testEnv);
}

@(
        testId
        ~ "Should use the internal headers in the binary even if -nostdinc is one of the compile flags")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_1/test_include_stdlibs.h", testEnv);
    // skip compiling, stdarg.h etc do not exist on all platforms
    p.skipCompile = Yes.skipCompile;
    runTestFile(p, testEnv);
}

@(testId ~ "Should ignore union declarations")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_1/unions.h", testEnv);
    p.compileFlags ~= "-DTEST_INCLUDE";
    runTestFile(p, testEnv);
}

@(testId ~ "Should be definitions of global variables for those that are extern")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_1/variables.h", testEnv);
    p.compileFlags ~= ["-DTEST_INCLUDE", "-DTEST_VARIABLES"];
    runTestFile(p, testEnv);
}

@(testId ~ "Should be an array using a macro for size")
unittest {
    //TODO Should use the original define (macro), not what it is replaced with
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_1/defines.h", testEnv);
    p.compileFlags ~= "-DTEST_INCLUDE";
    runTestFile(p, testEnv);
}

@(testId ~ "Should extract enums to Container")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_1/enum.h", testEnv);
    p.skipCompile = Yes.skipCompile;
    runTestFile(p, testEnv);
}

// --- Stage 2 ---

@(testId ~ "Should not overwrite an existing X_pre_includes or X_post_includes.hpp")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_2/no_overwrite.h", testEnv);
    p.compileIncls ~= "-I" ~ (p.root ~ "stage_2/include").toString;
    p.dexParams ~= ["--gen-pre-incl", "--gen-post-incl"];
    p.dexFlags ~= "-DPRE_INCLUDES";
    p.compileFlags ~= "-DPRE_INCLUDES";

    copy(p.root ~ "stage_2/no_overwrite_pre_includes.hpp",
            testEnv.outdir ~ "test_double_pre_includes.hpp");
    copy(p.root ~ "stage_2/no_overwrite_post_includes.hpp",
            testEnv.outdir ~ "test_double_post_includes.hpp");

    runTestFile(p, testEnv);
}

@(testId ~ "Includes shall be deduplicated to avoid the problem of multiple includes")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_2/bug_multiple_includes.h", testEnv);
    p.dexParams ~= ["--in=" ~ (p.root ~ "stage_2/bug_multiple_includes.h")
        .toString, "--in=" ~ (p.root ~ "stage_2/bug_multiple_includes.h").toString];
    runTestFile(p, testEnv);
}

// BEGIN Compilation Database Tests ##########################################

@(testId ~ "Should load compiler settings from compilation database")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("compile_db/single_file_main.c", testEnv);

    // find compilation flags by looking up how single_file_main.c was compiled
    p.dexParams ~= ["--compile-db=" ~ (p.root ~ "compile_db/single_file_db.json")
        .toString, "--file-restrict=.*/single_file.h"];

    p.compileIncls ~= "-I" ~ (p.root ~ "compile_db/dir1").toString;
    p.compileFlags ~= "-DDEXTOOL_TEST";

    p.mainf = p.root ~ Path("compile_db/single_file_main.cpp");
    runTestFile(p, testEnv);
}

@(testId ~ "Should fail with an error message when file not found in the compilation database")
unittest {
    mixin(envSetup(globalTestdir));
    auto r = makeDextool(testEnv)
        .throwOnExitStatus(false)
        .addInputArg(testData ~ "compile_db/file_not_found.c")
        .addArg(["--compile-db", (testData ~ "compile_db/single_file_db.json").toString])
        .run;

    r.success.shouldBeFalse;
    r.stderr.sliceContains("error: Unable to find any compiler flags for").shouldBeTrue;
}

@(testId ~ "shall derive the flags for parsing single_file.h via the #include in single_file_main.c in the compilation database")
@(Values(["compile_db/dir1/single_file.h", "use_file"], ["compile_db/single_file.h", "fallback"]))
unittest {
    mixin(envSetup(globalTestdir));
    testEnv.outputSuffix(getValue!(string[])[1]);
    testEnv.cleanOutdir;

    auto r = makeDextool(testEnv)
        .addArg(["--compile-db", (testData ~ "compile_db/single_file_db.json").toString])
        .addInputArg(getValue!(string[])[0])
        .run;

    r.stderr.sliceContains("error: Unable to find any compiler flags for").shouldBeFalse;
    // the file returned shall be the full path for the one searching for
    r.stderr.sliceContains("because it has an '#include' for '" ~ (testData ~ "compile_db/dir1/single_file.h").toString).shouldBeTrue;
}

@(testId ~ "Should load compiler settings from the second compilation database")
unittest {
    mixin(envSetup(globalTestdir));
    TestParams p;
    p.root = Path("testdata/compile_db").absolutePath;
    p.input_ext = p.root ~ Path("file2.h");
    p.out_hdr = testEnv.outdir ~ "test_double.hpp";

    // find compilation flags by looking up how single_file_main.c was compiled
    p.dexParams = ["ctestdouble", "--debug", "--compile-db=" ~ (p.root ~ "db1.json")
        .toString, "--compile-db=" ~ (p.root ~ "db2.json").toString];

    p.skipCompile = Yes.skipCompile;
    runTestFile(p, testEnv);
}

@(testId ~ "Should use the exact supplied --in=... as key when looking in compile db")
unittest {
    mixin(envSetup(globalTestdir));
    TestParams p;
    p.root = Path("testdata/compile_db").absolutePath;
    p.input_ext = p.root ~ Path("file2.h");
    p.out_hdr = testEnv.outdir ~ "test_double.hpp";

    p.dexParams = ["ctestdouble", "--debug",
        "--compile-db=" ~ (p.root ~ "db2.json").toString, "--in=file2.h"];

    p.skipCompile = Yes.skipCompile;
    p.skipCompare = Yes.skipCompare;
    runTestFile(p, testEnv);
}
// END   Compilation Database Tests ##########################################

// BEGIN CLI Tests ###########################################################

@(testId ~ "Should exclude many files from the generated test double")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_2/param_exclude_many_files.h", testEnv);
    p.dexParams ~= ["--file-exclude=.*/" ~ p.input_ext.baseName.toString,
        `--file-exclude='.*/include/b\.[h,c]'`];
    p.compileIncls ~= "-I" ~ (p.root ~ "stage_2/include").toString;
    p.compileFlags ~= ["-DTEST_INCLUDE"];

    p.dexFlags = p.compileIncls;

    runTestFile(p, testEnv);
}

@(testId ~ "Should exclude both main input file and all symbols from b*")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_2/param_exclude_match_all.h", testEnv);
    p.dexParams ~= ["--file-exclude=.*/param_exclude_match_all.*",
        `--file-exclude='.*/include/b\.c'`];
    p.compileIncls ~= "-I" ~ (p.root ~ "stage_2/include").toString;
    p.compileFlags ~= ["-DTEST_INCLUDE"];

    p.dexFlags = p.compileIncls;

    runTestFile(p, testEnv);
}

@(testId ~ "Should exclude this file from generation.")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_2/param_exclude_one_file.h", testEnv);
    p.compileIncls ~= "-I" ~ (p.root ~ "stage_2/include").toString;
    p.dexParams ~= "--file-exclude=.*/" ~ p.input_ext.baseName.toString;
    p.compileFlags ~= ["-DTEST_INCLUDE"];

    p.dexFlags = p.compileIncls;

    runTestFile(p, testEnv);
}

@(testId ~ "Should generate pre and post includes")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_2/param_gen_pre_post_include.h", testEnv);
    p.dexParams ~= ["--gen-pre-incl", "--gen-post-incl"];
    p.compileIncls ~= "-I" ~ (p.root ~ "stage_2/include").toString;
    p.skipCompare = Yes.skipCompare;

    runTestFile(p, testEnv);

    dextoolYap("Comparing");
    auto input = p.input_ext.stripExtension;
    compareResult(No.sortLines, Yes.skipComments,
                  GR(input ~ Ext(".hpp.ref"), p.out_hdr),
                  GR(input ~ Ext(".cpp.ref"), p.out_impl),
                  GR(input.up ~ "param_gen_pre_includes.hpp.ref", testEnv.outdir ~ "test_double_pre_includes.hpp"),
                  GR(input.up ~ "param_gen_post_includes.hpp.ref", testEnv.outdir ~ "test_double_post_includes.hpp"));
}

@(testId ~ "Should be all from this and b with the extra include stdio.h")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_2/param_include.h", testEnv);
    p.dexParams ~= ["--td-include=b.h", "--td-include=stdio.h"];
    p.compileIncls ~= "-I" ~ (p.root ~ "stage_2/include").toString;
    p.compileFlags ~= ["-DTEST_INCLUDE"];

    p.dexFlags = p.compileIncls;

    runTestFile(p, testEnv);
}

@(testId ~ "Should only be signatures from this file and b.h in the generated stub")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_2/param_restrict.h", testEnv);
    p.dexParams ~= ["--file-restrict=.*/" ~ p.input_ext.baseName.toString,
        "--file-restrict=.*/include/b.h"];
    p.compileIncls ~= "-I" ~ (p.root ~ "stage_2/include").toString;
    p.compileFlags ~= ["-DTEST_INCLUDE"];

    p.dexFlags = p.compileIncls;

    runTestFile(p, testEnv);
}

@(
        testId
        ~ "Should be a google mock of the interface used as callback from the C function implementations")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_2/param_gmock.h", testEnv);
    p.dexParams ~= "--gmock";
    p.dexFlags ~= ["-nostdinc", "-I" ~ (p.root ~ "stage_1").toString];
    p.compileFlags ~= ["-DTEST_INCLUDE", "-DTEST_FUNC_PTR", "-DTEST_FUNC",
        "-I" ~ (p.root ~ "stage_1").toString];
    runTestFile(p, testEnv);
}

@(testId ~ "Interface and adapter should be affected by parameter --main=X")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_2/param_main.h", testEnv);
    p.dexParams ~= ["--main=Stub", "--main-fname=stub"];
    p.out_hdr = p.out_hdr.up ~ "stub.hpp";
    p.out_impl = p.out_impl.up ~ "stub.cpp";
    p.compileFlags = [];
    runTestFile(p, testEnv);
}

@(testId ~ "Should process many files")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("compile_db/param_many_in.h", testEnv);

    p.input_ext = Path("");
    p.dexParams ~= ["--gmock", "--in=dir1/file1.h", "--in=dir1/file2.h",
        "--compile-db", (p.root ~ "compile_db/db.json").toString];
    p.compileIncls.length = 0;

    p.skipCompile = Yes.skipCompile;
    runTestFile(p, testEnv);
}

@(testId ~ "Should be location comments for globals and functions")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_2/param_loc_as_comment.h", testEnv);
    p.dexParams ~= ["--gmock", "--loc-as-comment"];
    p.compileFlags ~= ["-DTEST_INCLUDE"];

    runTestFile(p, testEnv);
}

@(testId ~ "Should be a custom header via CLI as string")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_2/param_custom_header.h", testEnv);
    p.dexParams ~= ["--gmock", "--header=// user $file$\n// header $file$"];

    p.skipCompile = Yes.skipCompile;
    runTestFile(p, testEnv, No.sortLines, No.skipComments);
}

@(testId ~ "Should be a custom header via CLI as filename")
unittest {
    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_2/param_custom_header.h", testEnv);
    p.dexParams ~= ["--gmock",
        "--header-file=" ~ (p.root ~ "stage_2/param_custom_header.txt").toString];

    p.skipCompile = Yes.skipCompile;
    runTestFile(p, testEnv, No.sortLines, No.skipComments);
}

@(testId ~ "Should be headers both from --in and derived from symbol locations")
unittest {
    // Test how --file-exclude and multiple --in interact to generate the
    // include's.
    // There is a bug where --in override include's that are needed.
    // expecting includes of b.h and c.h

    mixin(envSetup(globalTestdir));
    auto p = genTestParams("stage_2/header_include_bug.h", testEnv);
    p.dexParams ~= ["--in=" ~ (p.root ~ "stage_2/include/c.h").toString,
        "--file-exclude='.*/header_include_bug.h'"];
    p.dexFlags ~= "-I" ~ (p.root ~ "stage_2/include").toString;
    p.skipCompile = Yes.skipCompile;

    runTestFile(p, testEnv, No.sortLines, Yes.skipComments);
}

@(
        testId
        ~ "Generation of the ZeroGlobals implementation is controlled by the CLI flag --no-zeroglobals")
@Values(["yes", ""], ["no", "--no-zeroglobals"])
unittest {
    mixin(envSetup(globalTestdir, No.setupEnv));
    // don't overwrite the test result for the different tests
    testEnv.outputSuffix(getValue!(string[])[0]);
    testEnv.setupEnv;
    auto p = genTestParams("stage_2/param_no_zeroglobals.h", testEnv);

    p.dexParams ~= getValue!(string[])[1];
    p.compileFlags ~= ["-DTEST_INCLUDE"];

    if (getValue!(string[])[1].length == 0) {
        p.base_cmp = p.input_ext.dirName ~ "param_no_zeroglobals_yes";
    } else {
        p.base_cmp = p.input_ext.dirName ~ "param_no_zeroglobals_no";
    }

    runTestFile(p, testEnv);
}

@(testId ~ "Configuration data read from a file")
unittest {
    mixin(envSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "stage_2/config.h")
        .addArg(["--config", (testData ~ "stage_2/config.xml").toString])
        .addArg(["--compile-db=" ~ (testData ~ "stage_2/config.json").toString])
        .run;
    makeCompile(testEnv, testData ~ "stage_2")
        .addArg("-DTEST_INCLUDE")
        .run;
    makeCommand(testEnv, defaultBinary)
        .chdirToOutdir
        .run;
}

@(testId ~ "Only generate test doubles for those functions matching the symbol filter (restrict)")
unittest {
    mixin(envSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "stage_2/symbol.h")
        .addArg(["--config", (testData ~ "stage_2/symbol_restrict.xml").toString])
        .run;
    makeCompare(testEnv)
        .addCompare(testData ~ "stage_2/symbol.hpp.ref", "test_double.hpp")
        .run;
}

@(testId
        ~ "The test double shall NOT contain any of those symbols specified to be excluded by the symbol filter (exclude)")
unittest {
    mixin(envSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "stage_2/symbol.h")
        .addArg(["--config", (testData ~ "stage_2/symbol_exclude.xml").toString])
        .run;
    makeCompare(testEnv)
        .addCompare(testData ~ "stage_2/symbol.hpp.ref", "test_double.hpp")
        .run;
}

@(testId ~ "An error message containing what is wrong in the input xml file")
unittest {
    mixin(envSetup(globalTestdir));
    auto r = makeDextool(testEnv)
        .addInputArg(testData ~ "stage_2/param_config_with_errors.h")
        .addArg(["--config", (testData ~ "stage_2/param_config_with_errors.xml").toString])
        .throwOnExitStatus(false)
        .run;

    r.success.shouldBeFalse;
    r.stderr.sliceContains("Invalid xml file").shouldBeTrue;
    r.stderr.sliceContains("Line 2, column 1: Expected literal").shouldBeTrue;
}

// END   CLI Tests ###########################################################

// BEGIN Unspecified CLI Test ################################################

// This test could be anywhere. It just happens to be placed in the suite of C
// tests.
@(testId ~ "Shall exit with a help message that no such plugin is found")
unittest {
    mixin(envSetup(globalTestdir));

    auto r = dextool_test.makeDextool(testEnv)
        .addArg("invalid_plugin")
        .addArg("--debug")
        .throwOnExitStatus(false)
        .run;

    // an invalid plugin is always an error for the user
    r.success.shouldBeFalse;
    r.stderr.sliceContains("No such plugin found:").shouldBeTrue;
}

// END   Unspecified CLI Test ################################################

// BEGIN Stage 3 tests, functional ###########################################

@(testId ~ "Test using gtest/gmock")
unittest {
    mixin(envSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "stage_3/test1.h")
        .addArg("--gmock")
        .run;
    dextool_test.makeCompile(testEnv, "g++")
        .addArg(["-I", (testData ~ "stage_3").toString])
        .addArg(testData ~ "stage_3/test1_test.cpp")
        .addFilesFromOutdirWithExtension(".cpp", ["test_double_global.cpp"])
        .addGtestArgs
        .outputToDefaultBinary
        .run;
    makeCommand(testEnv, defaultBinary)
        .chdirToOutdir
        .run;
}

@(testId ~ "Test double of free functions shall be connected to the gmock instance")
unittest {
    mixin(envSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "stage_3/use_functions_mock.h")
        .addArg("--gmock")
        .run;
    dextool_test.makeCompile(testEnv, "g++")
        .addArg(["-I", (testData ~ "stage_3").toString])
        .addArg(testData ~ "stage_3/use_functions_mock_test.cpp")
        .addFilesFromOutdirWithExtension(".cpp", ["test_double_global.cpp"])
        .addGtestArgs
        .outputToDefaultBinary
        .run;
    makeCommand(testEnv, defaultBinary)
        .chdirToOutdir
        .run;
}

// END   Stage 3 #############################################################
