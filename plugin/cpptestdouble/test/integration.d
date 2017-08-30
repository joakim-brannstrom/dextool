/**
Copyright: Copyright (c) 2015-2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
 */
module dextool_test.integration;

import std.typecons : Flag, Yes, No;

import scriptlike;
import unit_threaded : shouldEqual;
import dextool_test.utils;

enum globalTestdir = "cpp_tests";

auto testData() {
    return Path("testdata/cpp").absolutePath;
}

auto makeDextool(const ref TestEnv env) {
    return dextool_test.utils.makeDextool(env).args(["cpptestdouble", "-d", "--gmock"]);
}

auto makeCompile(const ref TestEnv env) {
    return dextool_test.utils.makeCompile(env, "g++")
        .addArg(testData ~ "main_dev.cpp").outputToDefaultBinary;
}

auto makeCompile(const ref TestEnv env, Path srcdir) {
    return dextool_test.utils.makeCompile(env, "g++").addArg(["-I",
            srcdir.toString]).addArg(testData ~ "main_dev.cpp").outputToDefaultBinary;
}

struct TestParams {
    Flag!"skipCompare" skipCompare;
    Flag!"skipCompile" skipCompile;

    Path root;
    Path input_ext;
    Path out_hdr;
    Path out_impl;
    Path out_global;

    Path[] ref_gmock;
    Path[] out_gmock;

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

    p.root = testData.absolutePath;
    p.input_ext = p.root ~ Path(f);

    p.out_hdr = testEnv.outdir ~ "test_double.hpp";
    p.out_impl = testEnv.outdir ~ "test_double.cpp";
    p.out_global = testEnv.outdir ~ "test_double_global.cpp";

    p.dexParams = ["--DRT-gcopt=profile:1", "cpptestdouble", "--debug", "--gmock"];
    p.dexFlags = [];

    p.compileFlags = compilerFlags();
    p.compileIncls = ["-I" ~ p.input_ext.dirName.toString];

    p.mainf = p.root ~ Path("main_dev.cpp");
    p.binary = p.root ~ testEnv.outdir ~ "binary";

    return p;
}

TestParams genTestParams(string f, string[] mocks, const ref TestEnv testEnv) {
    auto p = genTestParams(f, testEnv);

    foreach (a; mocks) {
        p.ref_gmock ~= p.root ~ (format("%s_%s_gmock.hpp.ref", f.stripExtension, a));
        p.out_gmock ~= testEnv.outdir ~ format("test_double_%s_gmock.hpp", a);
    }

    return p;
}

void runTestFile(const ref TestParams p, ref TestEnv testEnv,
        Flag!"sortLines" sortLines = No.sortLines,
        Flag!"skipComments" skipComments = Yes.skipComments) {

    import unit_threaded : shouldEqual;

    dextoolYap("Input:%s", p.input_ext.raw);
    runDextool(p.input_ext, testEnv, p.dexParams, p.dexFlags);

    if (!p.skipCompare) {
        dextoolYap("Comparing");
        auto input = p.input_ext.stripExtension;
        // dfmt off
        compareResult(sortLines, skipComments,
                      GR(input ~ Ext(".hpp.ref"), p.out_hdr),
                      GR(input ~ Ext(".cpp.ref"), p.out_impl),
                      GR(Path(input.toString ~ "_global.cpp.ref"), p.out_global));
        // dfmt on
        foreach (a, b; lockstep(p.ref_gmock, p.out_gmock)) {
            compareResult(sortLines, skipComments, GR(a, b));
        }
    }

    if (!p.skipCompile) {
        dextoolYap("Compiling");
        compileResult(p.out_impl, p.binary, p.mainf, testEnv, p.compileFlags, p.compileIncls);
        runAndLog(p.binary).status.shouldEqual(0);
    }
}

// dfmt makes it hard to read the test cases.
// dfmt off

// --- Development tests ---

@(testId ~ "Should not segfault. Bug with anonymous namespace")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/bug_anon_namespace.hpp", testEnv);

    dextoolYap("Input:%s", p.input_ext.raw);
    runTestFile(p, testEnv);
}

@(testId ~ "Should not segfault or infinite recursion when poking at unexposed")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/bug_unexposed.hpp", testEnv);
    p.compileFlags ~= ["-DTEST_INCLUDE"];
    runTestFile(p, testEnv);
}

@(testId
        ~ "Should detect the type even though it is wchar_t. Bug: was treated specially which resulted in it never being set")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/bug_wchar.hpp", testEnv);
    p.dexParams ~= ["--file-restrict=.*bug_wchar.hpp", "--free-func"];
    p.compileFlags ~= ["-DTEST_INCLUDE"];
    runTestFile(p, testEnv);
}

@(testId ~ "Should be a google mock with a constant member method")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/class_const.hpp", ["simple"], testEnv);
    p.compileFlags ~= ["-DTEST_INCLUDE"];
    runTestFile(p, testEnv);
}

@(testId ~ "Should be gmocks that correctly implemented classes that inherit")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/class_inherit.hpp", ["a", "dup", "dupa",
            "ns1-ns2-ns2b", "ns1-ns2-ns2b", "ns1-ns1a", "virta", "virtb", "virtc"], testEnv);
    p.compileFlags ~= ["-DTEST_INCLUDE"];
    runTestFile(p, testEnv);
    // no free functions in the input so this file shall NOT be created.
    exists(testEnv.outdir ~ "test_double.cpp").shouldEqual(false);
}

@(testId
        ~ "Shall be gmocks without duplicated methods resulting in compilation error when multiple inheritance is used")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dev/class_inherit_bug.hpp")
        .run;
    makeCompare(testEnv)
        .addCompare(testData ~ "dev/class_inherit_bug_barf-a_gmock.hpp.ref", "test_double_barf-a_gmock.hpp")
        .addCompare(testData ~ "dev/class_inherit_bug_barf-b_gmock.hpp.ref", "test_double_barf-b_gmock.hpp")
        .addCompare(testData ~ "dev/class_inherit_bug_barf-interface-i1_gmock.hpp.ref", "test_double_barf-interface-i1_gmock.hpp")
        .run;
    makeCompile(testEnv, testData ~ "dev")
        .addArg("-DTEST_INCLUDE")
        .run;
}

@(testId ~ "Should be gmock with member methods and operators")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dev/class_interface.hpp")
        .run;
    makeCompare(testEnv)
        .addCompare(testData ~ "dev/class_interface.hpp.ref", "test_double.hpp")
        .run;
    makeCompile(testEnv, testData ~ "dev")
        .addArg("-DTEST_INCLUDE")
        .run;
}

@(testId ~ "Should be a gmock with more than 10 parameters")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dev/class_interface_more_than_10_params.hpp")
        .run;
    makeCompare(testEnv)
        .addCompare(testData ~ "dev/class_interface_more_than_10_params.hpp.ref", "test_double.hpp")
        .addCompare(testData ~ "dev/class_interface_more_than_10_params_simple_gmock.hpp.ref", "test_double_simple_gmock.hpp")
        .run;
    makeCompile(testEnv, testData ~ "dev")
        .addArg("-DTEST_INCLUDE")
        .run;
}

@(testId ~ "Should be a gmock impl for each class")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dev/class_multiple.hpp")
        .run;
    makeCompare(testEnv)
        .addCompare(testData ~ "dev/class_multiple_global1_gmock.hpp.ref", "test_double_global1_gmock.hpp")
        .addCompare(testData ~ "dev/class_multiple_global2_gmock.hpp.ref", "test_double_global2_gmock.hpp")
        .addCompare(testData ~ "dev/class_multiple_global3_gmock.hpp.ref", "test_double_global3_gmock.hpp")
        .addCompare(testData ~ "dev/class_multiple_ns-insidens1_gmock.hpp.ref", "test_double_ns-insidens1_gmock.hpp")
        .addCompare(testData ~ "dev/class_multiple_ns-ns2-insidens2_gmock.hpp.ref", "test_double_ns-ns2-insidens2_gmock.hpp")
        .run;
    makeCompile(testEnv, testData ~ "dev")
        .addArg("-DTEST_INCLUDE")
        .run;
}

@(testId ~ "Test common class patterns and there generated gmocks. See input file for info")
unittest {
    //TODO split input in many tests.
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dev/class_variants_interface.hpp")
        .run;
    makeCompare(testEnv)
            .addCompare(testData ~ "dev/class_variants_interface_inherit-derivedvirtual_gmock.hpp.ref",
                        "test_double_inherit-derivedvirtual_gmock.hpp")
            .addCompare(testData ~ "dev/class_variants_interface_no_inherit-allprotprivmadepublic_gmock.hpp.ref",
                        "test_double_no_inherit-allprotprivmadepublic_gmock.hpp")
            .addCompare(testData ~ "dev/class_variants_interface_no_inherit-commonpatternforpureinterface1_gmock.hpp.ref",
                        "test_double_no_inherit-commonpatternforpureinterface1_gmock.hpp")
            .addCompare(testData ~ "dev/class_variants_interface_no_inherit-commonpatternforpureinterface2_gmock.hpp.ref",
                        "test_double_no_inherit-commonpatternforpureinterface2_gmock.hpp")
            .addCompare(testData ~ "dev/class_variants_interface_no_inherit-ctornotaffectingvirtualclassificationaspure_gmock.hpp.ref",
                        "test_double_no_inherit-ctornotaffectingvirtualclassificationaspure_gmock.hpp")
            .addCompare(testData ~ "dev/class_variants_interface_no_inherit-ctornotaffectingvirtualclassificationasyes_gmock.hpp.ref",
                        "test_double_no_inherit-ctornotaffectingvirtualclassificationasyes_gmock.hpp")
            .addCompare(testData ~ "dev/class_variants_interface_no_inherit-virtualwithdtor_gmock.hpp.ref",
                        "test_double_no_inherit-virtualwithdtor_gmock.hpp")
            .run;
    makeCompile(testEnv, testData ~ "dev")
        .addArg("-DTEST_INCLUDE")
        .run;
}

@(testId ~ "Should exclude self from generated test double")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dev/exclude_self.hpp")
        .addArg("--file-exclude=.*/dev/exclude_self.hpp")
        .addArg("--free-func")
        .addFlag(["-I", (testData ~ "dev/extra").toString])
        .run;
    makeCompare(testEnv)
        .addCompare(testData ~ "dev/exclude_self.hpp.ref", "test_double.hpp")
        .addCompare(testData ~ "dev/exclude_self.cpp.ref", "test_double.cpp")
        .run;
    makeCompile(testEnv, testData ~ "dev")
        .addArg(["-I", (testData ~ "dev/extra").toString])
        .addArg("-DTEST_INCLUDE")
        .run;
}

@(testId ~ "Should generate implementation of functions in ns and externs")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dev/extern_in_ns.hpp")
        .addArg("--free-func")
        .addFlag(["-I", (testData ~ "dev/extra").toString])
        .run;
    makeCompare(testEnv)
        .addCompare(testData ~ "dev/extern_in_ns.hpp.ref", "test_double.hpp")
        .addCompare(testData ~ "dev/extern_in_ns.cpp.ref", "test_double.cpp")
        .run;
    makeCompile(testEnv, testData ~ "dev")
        .addArg(["-I", (testData ~ "dev/extra").toString])
        .addArg("-DTEST_INCLUDE")
        .run;
}

@(testId ~ "Shall generate a test double for the free function")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dev/one_free_func.hpp")
        .addArg("--free-func")
        .run;
    makeCompare(testEnv)
        .addCompare(testData ~ "dev/one_free_func.hpp.ref", "test_double.hpp")
        .addCompare(testData ~ "dev/one_free_func.cpp.ref", "test_double.cpp")
        .run;
    makeCompile(testEnv, testData ~ "dev")
        .addArg("-DTEST_INCLUDE")
        .run;
}

@(testId ~ "Should generate test doubles for free functions in namespaces")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dev/functions_in_ns.hpp")
        .addArg("--free-func")
        .run;
    makeCompare(testEnv)
        .addCompare(testData ~ "dev/functions_in_ns.hpp.ref", "test_double.hpp")
        .addCompare(testData ~ "dev/functions_in_ns_ns-testdouble-i_testdouble_gmock.hpp.ref", "test_double_ns-testdouble-i_testdouble_gmock.hpp")
        .addCompare(testData ~ "dev/functions_in_ns_ns_using_scope-ns_using_inner-testdouble-i_testdouble_gmock.hpp.ref", "test_double_ns_using_scope-ns_using_inner-testdouble-i_testdouble_gmock.hpp")
        .run;
    makeCompile(testEnv, testData ~ "dev")
        .addArg("-DTEST_INCLUDE")
        .run;
}

@(testId ~ "Should use root as include")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv).addInputArg(testData ~ "dev/have_root.hpp")
        .addArg("--free-func")
        .addFlag(["-I", (testData ~ "dev/extra").toString])
        .run;
    makeCompare(testEnv)
        .addCompare(testData ~ "dev/have_root.hpp.ref", "test_double.hpp")
        .addCompare(testData ~ "dev/have_root.cpp.ref", "test_double.cpp")
        .run;
    makeCompile(testEnv, testData ~ "dev")
        .addArg(["-I", (testData ~ "dev/extra").toString])
        .addArg("-DTEST_INCLUDE")
        .run;
}

@(testId ~ "Test --file-restrict")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv).addInputArg(testData ~ "dev/param_restrict.hpp")
        .addArg(["--file-restrict", ".*/" ~ (testData ~ "dev").toString])
        .addArg("--file-restrict=.*/b.hpp")
        .addFlag(["-I", (testData ~ "dev/extra").toString])
        .run;
    makeCompile(testEnv)
        .addArg("-DTEST_INCLUDE")
        .addArg(["-I", (testData ~ "dev/extra").toString])
        .run;
}

@(testId ~ "Should load compiler settings from compilation database")
unittest {
    mixin(EnvSetup(globalTestdir));
    // find compilation flags by looking up how single_file_main.c was compiled
    makeDextool(testEnv).addInputArg(testData ~ "compile_db/single_file_main.hpp")
        .addArg("--free-func")
        .addArg(["--compile-db", (testData ~ "compile_db/single_file_db.json").toString])
        .addArg("--file-restrict=.*/single_file.hpp")
        .run;
    dextool_test.utils.makeCompile(testEnv, "g++")
        .addArg(["-I", (testData ~ "compile_db/dir1").toString])
        .addArg("-DDEXTOOL_TEST")
        .addArg(testData ~ "compile_db/single_file_main.cpp")
        .run;
}

@(testId ~ "Should not crash when std::system_error isn't found during analyze")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv).addInputArg(testData ~ "dev/bug_class_not_in_ast.hpp")
        .run;
}

@(testId ~ "Should be a gmock of the class that is NOT forward declared")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dev/class_forward_decl.hpp")
        .run;
    makeCompare(testEnv)
        .addCompare(testData ~ "dev/class_forward_decl.hpp.ref", "test_double.hpp")
        .addCompare(testData ~ "dev/class_forward_decl_normal_gmock.hpp.ref", "test_double_normal_gmock.hpp")
        .run;
}

@(testId ~ "Shall merge all occurences of namespace ns1")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dev/ns_merge.hpp").addArg("--free-func")
        .run;
    makeCompare(testEnv).addCompare(testData ~ "dev/ns_merge.hpp.ref", "test_double.hpp")
        .run;
}

@(testId ~ "Includes shall be deduplicated to avoid the problem of multiple includes")
unittest {
    mixin(envSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "stage_2/bug_multiple_includes.hpp")
        .addArg("--free-func")
        .run;
    makeCompare(testEnv).addCompare(testData ~ "stage_2/bug_multiple_includes.hpp.ref", "test_double.hpp").run;
    makeCompile(testEnv).run;
}

@(testId ~ "Should generate pre and post includes")
unittest {
    mixin(envSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "stage_2/param_gen_pre_post_include.hpp")
        .addArg("--gen-pre-incl")
        .addArg("--gen-post-incl")
        .addFlag(["-I", (testData ~ "stage_2/include").toString])
        .run;
    makeCompare(testEnv)
        .addCompare(testData ~ "stage_2/param_gen_pre_post_include.hpp.ref", "test_double.hpp")
        .addCompare(testData ~ "stage_2/param_gen_pre_includes.hpp.ref", "test_double_pre_includes.hpp")
        .addCompare(testData ~ "stage_2/param_gen_post_includes.hpp.ref", "test_double_post_includes.hpp")
        .run;
    makeCompile(testEnv).run;
}

// BEGIN CLI Tests ###########################################################

@(testId ~ "Should be a custom header via CLI as string")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dev/param_custom_header.hpp")
        .addArg("--free-func")
        .addArg("--header=// user $file$\n// header $file$")
        .run;
    makeCompare(testEnv)
        .addCompare(testData ~ "dev/param_custom_header.hpp.ref", "test_double.hpp")
        .addCompare(testData ~ "dev/param_custom_header.cpp.ref", "test_double.cpp")
        .addCompare(testData ~ "dev/param_custom_header_testdouble-i_testdouble_gmock.hpp.ref",
                    "test_double_testdouble-i_testdouble_gmock.hpp")
        .skipComments(false)
        .run;
    makeCompile(testEnv).run;
}

@(testId ~ "Should be a custom header via CLI as filename")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dev/param_custom_header.hpp")
        .addArg("--free-func")
        .addArg(["--header-file", (testData ~ "dev/param_custom_header.txt").toString])
        .run;
    makeCompare(testEnv)
        .addCompare(testData ~ "dev/param_custom_header_testdouble-i_testdouble_gmock.hpp.ref",
                    "test_double_testdouble-i_testdouble_gmock.hpp")
        .skipComments(false)
        .run;
    makeCompile(testEnv).run;
}

@(testId ~ "Configuration data read from a file")
unittest {
    mixin(envSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "stage_2/config.hpp")
        .addArg(["--config",(testData ~ "stage_2/config.xml").toString])
        .addArg(["--compile-db",(testData ~ "stage_2/config.json").toString])
        .addFlag("-DTEST_INCLUDE")
        .run;
    makeCompile(testEnv).run;
}

// END   CLI Tests ###########################################################
