/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This file contains the stage_1 test cases that do not have any other suitable
category to put them in.
*/
module dextool_test.stage_1;

import std.typecons : Flag, Yes, No;
import std.file : isFile, readText;
import std.algorithm : splitter;
import std.array : array;

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

@(testId ~ "shall check _logs.xml for correct logging of flags")
unittest {
    mixin(envSetup(globalTestdir));
    makeDextool(testEnv)
        // --gmock is added in the makeDextool-call
        .addInputArg(testData ~ "dev/class_inherit.hpp")
        .run;
    makeCompile(testEnv, testData ~ "dev")
        .addArg("-DTEST_INCLUDE")
        .run;

    auto file = testEnv.outdir.escapePath ~ "/test_double_log.xml";

    assert(isFile(file));

    auto log = readText(file).splitter("\n").array();
    auto commands = ["--gmock",
                    "--in",
                    "dev/class_inherit.hpp"];

    testAnyOrder!SubStr(commands).shouldBeIn(log);
}

@(testId ~ "shall check _log.xml for correct logging of flags and include-paths")
unittest {
    mixin(envSetup(globalTestdir));
    makeDextool(testEnv)
        // --gmock is added in the makeDextool-call
        .addArg("--free-func")
        .addInputArg(testData ~ "dev/class_multiple.hpp")
        .addIncludeFlag("/arbitrary/include/path/")
        .addIncludeFlag("/another/arbitrary/include/path/")
        .run;
    makeCompile(testEnv, testData ~ "dev")
        .addArg("-DTEST_INCLUDE")
        .run;

    auto file = testEnv.outdir.escapePath ~ "/test_double_log.xml";

    assert(isFile(file));

    auto log = readText(file).splitter("\n").array();
    auto commands = ["--gmock",
                    "--free-func",
                    "--in",
                    "dev/class_multiple.hpp",
                    "-I /arbitrary/include/path/",
                    "-I /another/arbitrary/include/path/"];

    testAnyOrder!SubStr(commands).shouldBeIn(log);
}

@(testId ~ "shall check _log.xml for a command not executed")
unittest {
    mixin(envSetup(globalTestdir));
    makeDextool(testEnv)
        // --gmock is added in the makeDextool-call
        .addInputArg(testData ~ "dev/class_multiple.hpp")
        .run;
    makeCompile(testEnv, testData ~ "dev")
        .addArg("-DTEST_INCLUDE")
        .run;

    auto file = testEnv.outdir.escapePath ~ "/test_double_log.xml";

    assert(isFile(file));

    auto log = readText(file).splitter("\n").array();
    auto command = ["--free-func"]; // not added or executed in testEnv

    testAnyOrder!SubStr(command).shouldNotBeIn(log);
}
