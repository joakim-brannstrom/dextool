/**
Copyright: Copyright (c) 2015-2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
 */
module dextool_test.integration;

import std.typecons : Flag, Yes, No;

import dextool_test.utility;

// dfmt makes it hard to read the test cases.
// dfmt off

// --- Development tests ---

@(testId ~ "Should not segfault. Bug with anonymous namespace")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dev/bug_anon_namespace.hpp")
        .run;
    makeCompile(testEnv, testData ~ "dev").run;
}

@(testId ~ "Should not segfault or infinite recursion when poking at unexposed")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dev/bug_unexposed.hpp")
        .run;
    makeCompile(testEnv, testData ~ "dev")
        .addArg("-DTEST_INCLUDE")
        .run;
}

@(testId
        ~ "Should detect the type even though it is wchar_t. Bug: was treated specially which resulted in it never being set")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dev/bug_wchar.hpp")
        .addArg(["--file-include", ".*bug_wchar.hpp"])
        .addArg("--free-func")
        .run;
    makeCompare(testEnv)
        .addCompare(testData ~ "dev/bug_wchar.hpp.ref", "test_double.hpp")
        .run;
    makeCompile(testEnv, testData ~ "dev")
        .addArg("-DTEST_INCLUDE")
        .run;
}

@(testId ~ "Should be a google mock with a constant member method")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dev/class_const.hpp")
        .run;
    makeCompare(testEnv)
        .addCompare(testData ~ "dev/class_const_simple_gmock.hpp.ref", "test_double_simple_gmock.hpp")
        .run;
    makeCompile(testEnv, testData ~ "dev")
        .addArg("-DTEST_INCLUDE")
        .run;
}

@(testId ~ "Should be gmocks that correctly implemented classes that inherit")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dev/class_inherit.hpp")
        .run;
    makeCompare(testEnv)
        .addCompare(testData ~ "dev/class_inherit_a_gmock.hpp.ref", "test_double_a_gmock.hpp")
        .addCompare(testData ~ "dev/class_inherit_dup_gmock.hpp.ref", "test_double_dup_gmock.hpp")
        .addCompare(testData ~ "dev/class_inherit_dupa_gmock.hpp.ref", "test_double_dupa_gmock.hpp")
        .addCompare(testData ~ "dev/class_inherit_ns1-ns2-ns2b_gmock.hpp.ref", "test_double_ns1-ns2-ns2b_gmock.hpp")
        .addCompare(testData ~ "dev/class_inherit_ns1-ns1a_gmock.hpp.ref", "test_double_ns1-ns1a_gmock.hpp")
        .addCompare(testData ~ "dev/class_inherit_virta_gmock.hpp.ref", "test_double_virta_gmock.hpp")
        .addCompare(testData ~ "dev/class_inherit_virtb_gmock.hpp.ref", "test_double_virtb_gmock.hpp")
        .addCompare(testData ~ "dev/class_inherit_virtc_gmock.hpp.ref", "test_double_virtc_gmock.hpp")
        .run;
    makeCompile(testEnv, testData ~ "dev")
        .addArg("-DTEST_INCLUDE")
        .run;
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

@(testId ~ "Test --file-include")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv).addInputArg(testData ~ "dev/param_restrict.hpp")
        .addArg("--file-include=.*/b.hpp")
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
        .addArg("--file-include=.*/single_file.hpp")
        .run;
    dextool_test.makeCompile(testEnv, "g++")
        .addArg(["-I", (testData ~ "compile_db/dir1").toString])
        .addArg("-DDEXTOOL_TEST")
        .addArg(testData ~ "compile_db/single_file_main.cpp")
        .run;
}

@(testId ~ "Should not crash when std::system_error isn't found during analyze")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(testData ~ "dev/bug_class_not_in_ast.hpp")
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
