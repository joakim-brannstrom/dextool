/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.gtest_integration;

import dextool_test.utility;

// dfmt off

@("shall pretty print the struct")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(pluginTestData ~ "stage_3/pretty_print.hpp")
        .run;
    dextool_test.makeCompile(testEnv, "g++")
        .addInclude(pluginTestData ~ "stage_3")
        .addArg(pluginTestData ~ "stage_3/pretty_print.cpp")
        .addFileFromOutdir("test_double_fused_gtest.cpp")
        .addGtestArgs
        .outputToDefaultBinary
        .run;
    makeCommand(testEnv, defaultBinary)
        .run;
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

    exists(testEnv.outdir ~ "test_double_pod_empty_gtest.hpp").shouldBeFalse;
    exists(testEnv.outdir ~ "test_double_pod_only_private_gtest.hpp").shouldBeFalse;
    exists(testEnv.outdir ~ "test_double_pod_only_protected_gtest.hpp").shouldBeFalse;

    makeCompile(testEnv, pluginTestData ~ "stage_1")
        .addFileFromOutdir("test_double_fused_gtest.cpp")
        .addGtestArgs
        .run;
}
