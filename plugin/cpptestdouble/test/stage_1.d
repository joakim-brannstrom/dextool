/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This file contains the stage_1 test cases that do not have any other suitable
category to put them in.
*/
module dextool_test.stage_1;

import std.typecons : Flag, Yes, No;

import dextool_test.utility;

// dfmt makes it hard to read the test cases.
// dfmt off

@(testId ~ "shall produce a mock from a derived class. The methods in the produced mock shall have a unique signature. This case test same signature in the derived- and super class where the parameters have different names for the same method")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv)
        .addInputArg(pluginTestData ~ "stage_1/bug_class_inherit.hpp")
        .run;
    dextool_test.makeCompile(testEnv, "g++")
        .addInclude(pluginTestData ~ "stage_1")
        .addArg(pluginTestData ~ "stage_1/bug_class_inherit.cpp")
        .outputToDefaultBinary
        .addGtestArgs
        .run;
}
