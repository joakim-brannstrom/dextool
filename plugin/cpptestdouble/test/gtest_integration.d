/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.gtest_integration;

import std.file : exists;
import std.path : buildPath;

import dextool_test.utility;

// dfmt off

@("shall pretty print the struct")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(pluginTestData ~ "stage_3/pretty_print.hpp")
        .addArg(["--file-restrict", (pluginTestData ~ "stage_3").toString ~ ".*"])
        .run;
    dextool_test.makeCompile(testEnv, "g++")
        .addInclude(pluginTestData ~ "stage_3")
        .addArg(pluginTestData ~ "stage_3/pretty_print.cpp")
        .addFileFromOutdir("test_double_fused_gtest.cpp")
        .addGtestArgs
        .outputToDefaultBinary
        .run;
    auto r = makeCommand(testEnv, defaultBinary).run;

    r.stdout.sliceContains([
        "begin: test_expect_eq",
        "Equal check passed",
        "",
        "Expected: a",
        "Which is: int_:1 long_:2 float_:3 double_:4 long_double_:5 char_:'a' (97, 0x61) myInt_:2 myPod_:x:2",
        "To be equal to: b",
        "Which is: int_:2 long_:2 float_:3 double_:4 long_double_:5 char_:'a' (97, 0x61) myInt_:2 myPod_:x:2",
        "",
        "Expected: a",
        "Which is: int_:1 long_:2 float_:3 double_:4 long_double_:5 char_:'a' (97, 0x61) myInt_:2 myPod_:x:2",
        "To be equal to: b",
        "Which is: int_:1 long_:1 float_:3 double_:4 long_double_:5 char_:'a' (97, 0x61) myInt_:2 myPod_:x:2",
        "",
        "Expected: a",
        "Which is: int_:1 long_:2 float_:3 double_:4 long_double_:5 char_:'a' (97, 0x61) myInt_:2 myPod_:x:2",
        "To be equal to: b",
        "Which is: int_:1 long_:2 float_:2 double_:4 long_double_:5 char_:'a' (97, 0x61) myInt_:2 myPod_:x:2",
        "",
        "Expected: a",
        "Which is: int_:1 long_:2 float_:3 double_:4 long_double_:5 char_:'a' (97, 0x61) myInt_:2 myPod_:x:2",
        "To be equal to: b",
        "Which is: int_:1 long_:2 float_:3 double_:2 long_double_:5 char_:'a' (97, 0x61) myInt_:2 myPod_:x:2",
        "",
        "Expected: a",
        "Which is: int_:1 long_:2 float_:3 double_:4 long_double_:5 char_:'a' (97, 0x61) myInt_:2 myPod_:x:2",
        "To be equal to: b",
        "Which is: int_:1 long_:2 float_:3 double_:4 long_double_:2 char_:'a' (97, 0x61) myInt_:2 myPod_:x:2",
        "",
        "Expected: a",
        "Which is: int_:1 long_:2 float_:3 double_:4 long_double_:5 char_:'a' (97, 0x61) myInt_:2 myPod_:x:2",
        "To be equal to: b",
        "Which is: int_:1 long_:2 float_:3 double_:4 long_double_:5 char_:'b' (98, 0x62) myInt_:2 myPod_:x:2",
        "",
        "Expected: a",
        "Which is: int_:1 long_:2 float_:3 double_:4 long_double_:5 char_:'a' (97, 0x61) myInt_:2 myPod_:x:2",
        "To be equal to: b",
        "Which is: int_:1 long_:2 float_:3 double_:4 long_double_:5 char_:'a' (97, 0x61) myInt_:1 myPod_:x:2",
        "",
        "Expected: a",
        "Which is: int_:1 long_:2 float_:3 double_:4 long_double_:5 char_:'a' (97, 0x61) myInt_:2 myPod_:x:2",
        "To be equal to: b",
        "Which is: int_:1 long_:2 float_:3 double_:4 long_double_:5 char_:'a' (97, 0x61) myInt_:2 myPod_:x:3",
        "end: test_expect_eq",
        ]);
    r.stdout.sliceContains([
        "begin: test_c_aggregate_eq",
        "Equal check passed",
        "",
        "Expected: agg_a",
        `Which is: bool_arr:{ true, false } int_arr:{ 1, 2 } double_arr:{ 0, 0 } char_arr:"a"`,
        "To be equal to: agg_b",
        `Which is: bool_arr:{ true, true } int_arr:{ 1, 2 } double_arr:{ 0, 0 } char_arr:"a"`,
        "",
        "Expected: agg_a",
        `Which is: bool_arr:{ true, false } int_arr:{ 1, 2 } double_arr:{ 0, 0 } char_arr:"a"`,
        "To be equal to: agg_b",
        `Which is: bool_arr:{ true, false } int_arr:{ 1, 3 } double_arr:{ 0, 0 } char_arr:"a"`,
        "",
        "Expected: agg_a",
        `Which is: bool_arr:{ true, false } int_arr:{ 1, 2 } double_arr:{ 0, 0 } char_arr:"a"`,
        "To be equal to: agg_b",
        `Which is: bool_arr:{ true, false } int_arr:{ 1, 2 } double_arr:{ 0, 3.5 } char_arr:"a"`,
        "",
        "Expected: agg_a",
        `Which is: bool_arr:{ true, false } int_arr:{ 1, 2 } double_arr:{ 0, 0 } char_arr:"a"`,
        "To be equal to: agg_b",
        `Which is: bool_arr:{ true, false } int_arr:{ 1, 2 } double_arr:{ 0, 0 } char_arr:"b"`,
        "end: test_c_aggregate_eq",
    ]).shouldBeTrue;
    r.stdout.sliceContains([
        "begin: test_pp_of_nested_struct",
        "",
        "Expected: a",
        "Which is: x:inner_member_a:1 inner_member_b:0 y:0",
        "To be equal to: b",
        "Which is: x:inner_member_a:2 inner_member_b:3 y:4",
        "end: test_pp_of_nested_struct",
        "Passed",
    ]).shouldBeTrue;
}

@("shall generate pretty printers for structs in a namespace")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(pluginTestData ~ "stage_3/test_pretty_print_in_ns.hpp")
        .run;
    dextool_test.makeCompile(testEnv, "g++")
        .addInclude(pluginTestData ~ "stage_3")
        .addArg(pluginTestData ~ "stage_3/test_pretty_print_in_ns.cpp")
        .addFileFromOutdir("test_double_fused_gtest.cpp")
        .addGtestArgs
        .outputToDefaultBinary
        .run;
    auto r = makeCommand(testEnv, defaultBinary)
        .run;

    r.stdout.sliceContains([
                           "Expected: a",
                           "Which is: x:1",
                           "To be equal to: b",
                           "Which is: x:2",
    ]);

    r.stdout.sliceContains([
      "Expected: a",
      "Which is: y:1",
      "To be equal to: b",
      "Which is: y:2"
    ]);
}

@("shall generate pretty printers for structs that have public members")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(pluginTestData ~ "stage_1/test_pretty_print_generator.hpp")
        .run;

    exists((testEnv.outdir ~ "test_double_pod_empty_gtest.hpp").toString).shouldBeFalse;
    exists((testEnv.outdir ~ "test_double_pod_only_private_gtest.hpp").toString).shouldBeFalse;
    exists((testEnv.outdir ~ "test_double_pod_only_protected_gtest.hpp").toString).shouldBeFalse;

    makeCompile(testEnv, pluginTestData ~ "stage_1")
        .addFileFromOutdir("test_double_fused_gtest.cpp")
        .addGtestArgs
        .run;
}
