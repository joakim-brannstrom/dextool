/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.integration;

import scriptlike;
import unit_threaded : shouldEqual, shouldBeTrue, shouldBeFalse;

import dextool_test.utils;

enum globalTestdir = "analyze_tests";

immutable mcCabeJsonFile = "result_mccabe.json";

auto testData() {
    return Path("plugin_testdata").absolutePath;
}

auto makeDextool(const ref TestEnv testEnv) {
    return dextool_test.utils.makeDextool(testEnv).args(["analyze", "--mccabe"]);
}

auto readMcCabe(const ref TestEnv testEnv) {
    // dfmt off
    return std.file.readText((testEnv.outdir ~ mcCabeJsonFile).toString)
        .splitLines
        // remove locations because they are absolute path and those can be
        // mapped to a "function" if needed
        .filter!(a => a.indexOf(`"location":`) == -1)
        .array();
    // dfmt on
}

@(testId ~ "McCabe: shall report a McCabe value for each function")
unittest {
    mixin(envSetup(globalTestdir));

    auto r = makeDextool(testEnv).addInputArg(testData ~ "function_nesting_if.c")
        .addArg("--mccabe-threshold=1").run;

    r.stdout.sliceContains("McCabe:2 a").shouldBeTrue;
    r.stdout.sliceContains("McCabe:3 b").shouldBeTrue;
}

@(testId ~ "McCabe: the dump to stdout and the json value shall be equivalent")
unittest {
    mixin(envSetup(globalTestdir));

    auto r = makeDextool(testEnv).addInputArg(testData ~ "function_simple.c")
        .addArg("--mccabe-threshold=1").run;

    // shall be dumped to stdout
    r.stdout.sliceContains(`McCabe:1 f`).shouldBeTrue;
    // shall be reported with the same value in the json file
    readMcCabe(testEnv).sliceContains([`"function":"f",`, `"mccabe":1`]).shouldBeTrue;
}

@(testId ~ "McCabe: shall report the McCabe value for functions in namespaces")
unittest {
    mixin(envSetup(globalTestdir));

    auto r = makeDextool(testEnv).addInputArg(testData ~ "function_in_namespace.cpp")
        .addArg("--mccabe-threshold=1").run;

    r.stdout.sliceContains("McCabe:1 f").shouldBeTrue;
}

@(testId ~ "McCabe: shall not crash when encountering class and function declarations")
unittest {
    mixin(envSetup(globalTestdir));

    auto r = makeDextool(testEnv).addInputArg(testData ~ "only_declarations.cpp").run;

    r.stdout.sliceContains(`McCabe:`).shouldBeFalse;
}

@(testId ~ "McCabe: shall report value for all functions in namespaces (even anonymous)")
unittest {
    mixin(envSetup(globalTestdir));

    auto r = makeDextool(testEnv).addInputArg(testData ~ "function_in_namespace.cpp")
        .addArg("--mccabe-threshold=1").run;

    r.stdout.sliceContains(`McCabe:1 func_in_anonymous`).shouldBeTrue;
    r.stdout.sliceContains(`McCabe:1 f`).shouldBeTrue;
    r.stdout.sliceContains(`McCabe:1 g`).shouldBeTrue;
}

@("shall be a valid json file")
unittest {
    import std.json;

    mixin(envSetup(globalTestdir));

    auto r = makeDextool(testEnv).addInputArg(testData ~ "function_simple.c")
        .addArg("--mccabe-threshold=1").run;

    // will throw if the json file is invalid
    auto json = std.file.readText((testEnv.outdir ~ mcCabeJsonFile).toString).parseJSON;
}

@(
        testId
        ~ "McCabe: shall report the total McCabe value of all functions in the file (regardless of threshold)")
unittest {
    mixin(envSetup(globalTestdir));

    auto r = makeDextool(testEnv).addInputArg(testData ~ "function_simple.c").run;

    r.stdout.sliceContains(["Files:", `McCabe:2`]).shouldBeTrue;
}

@(testId ~ "McCabe: shall only report functions with a McCabe value equal to or above the threshold")
unittest {
    mixin(envSetup(globalTestdir));

    auto r = makeDextool(testEnv).addInputArg(testData ~ "test_threshold.cpp")
        .addArg("--mccabe-threshold=5").run;

    r.stdout.sliceContains(["Functions:", "McCabe:1"]).shouldBeFalse;
    r.stdout.sliceContains(["Functions:", "McCabe:3"]).shouldBeFalse;
    r.stdout.sliceContains(["Functions:", "McCabe:4"]).shouldBeFalse;
    r.stdout.sliceContains(["Functions:", "McCabe:5 f_5", "McCabe:9 f_9"]).shouldBeTrue;
}

@("McCabe: shall report the McCabe value for class methods")
unittest {
    mixin(envSetup(globalTestdir));

    auto r = makeDextool(testEnv).addInputArg(testData ~ "test_class_methods.cpp")
        .addArg("--mccabe-threshold=1").run;

    r.stdout.sliceContains(["Files:", "McCabe:7"]).shouldBeTrue;
    // dfmt off
    // methods
    r.stdout.sliceContains(["Functions:",
                           "McCabe:1 A", // constructor
                           "McCabe:1 A", // constructor
                           "McCabe:1 inline_", // method
                           "McCabe:1 operator bool", // conversion function
                           "McCabe:1 operator=", // method
                           "McCabe:1 outside", // method
                           "McCabe:1 ~A", // destructor
    ]).shouldBeTrue;
    // dfmt on
}
