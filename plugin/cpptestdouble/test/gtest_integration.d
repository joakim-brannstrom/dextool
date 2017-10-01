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
