/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.integration;

import std.array : array;
import std.algorithm : filter;
import std.string : splitLines, indexOf;
import std.file : readText;

import unit_threaded : shouldEqual, shouldBeTrue, shouldBeFalse;

import dextool_test;

enum globalTestdir = "analyze_tests";

immutable mcCabeJsonFile = "result_mccabe.json";

auto testData() {
    return Path("plugin_testdata");
}

auto makeDextool(const ref TestEnv testEnv) {
    return dextool_test.makeDextool(testEnv).args(["analyze", "--mccabe"]);
}

auto readMcCabe(const ref TestEnv testEnv) {
    // dfmt off
    return readText((testEnv.outdir ~ mcCabeJsonFile).toString)
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
        .addArg("--mccabe-threshold=1").addArg("--output-stdout").run;

    r.output.sliceContains("2      a").shouldBeTrue;
    r.output.sliceContains("3      b").shouldBeTrue;
}

@(testId ~ "McCabe: the dump to stdout and the json value shall be equivalent")
unittest {
    mixin(envSetup(globalTestdir));

    auto r = makeDextool(testEnv).addInputArg(testData ~ "function_simple.c")
        .addArg("--mccabe-threshold=1").addArg("--output-json").addArg("--output-stdout").run;

    // shall be dumped to stdout
    r.output.sliceContains(`1      f`).shouldBeTrue;
    r.output.sliceContains(`==Total McCabe 1`);
    // shall be reported with the same value in the json file
    readMcCabe(testEnv).sliceContains([`"function":"f",`, `"mccabe":1`]).shouldBeTrue;
    readMcCabe(testEnv).sliceContains([`"total_mccabe":2`]).shouldBeTrue;
}

@(testId ~ "McCabe: shall report the McCabe value for functions in namespaces")
unittest {
    mixin(envSetup(globalTestdir));

    auto r = makeDextool(testEnv).addInputArg(testData ~ "function_in_namespace.cpp")
        .addArg("--output-stdout").addArg("--mccabe-threshold=1").run;

    r.output.sliceContains("1      f").shouldBeTrue;
}

@(testId ~ "McCabe: shall not crash when encountering class and function declarations")
unittest {
    mixin(envSetup(globalTestdir));

    auto r = makeDextool(testEnv).addInputArg(testData ~ "only_declarations.cpp")
        .addArg("--output-stdout").run;

    r.output.sliceContains(`1   `).shouldBeFalse;
}

@(testId ~ "McCabe: shall report value for all functions in namespaces (even anonymous)")
unittest {
    mixin(envSetup(globalTestdir));

    auto r = makeDextool(testEnv).addInputArg(testData ~ "function_in_namespace.cpp")
        .addArg("--output-stdout").addArg("--mccabe-threshold=1").run;

    r.output.sliceContains(`1      func_in_anonymous`).shouldBeTrue;
    r.output.sliceContains(`1      f`).shouldBeTrue;
    r.output.sliceContains(`1      g`).shouldBeTrue;
}

@(testId ~ "shall be a valid json file")
unittest {
    import std.json;

    mixin(envSetup(globalTestdir));

    auto r = makeDextool(testEnv).addInputArg(testData ~ "function_simple.c")
        .addArg("--output-json").addArg("--mccabe-threshold=1").run;

    // will throw if the json file is invalid
    auto json = readText((testEnv.outdir ~ mcCabeJsonFile).toString).parseJSON;
}

@(
        testId
        ~ "McCabe: shall report the total McCabe value of all functions in the file (regardless of threshold)")
unittest {
    mixin(envSetup(globalTestdir));

    auto r = makeDextool(testEnv).addInputArg(testData ~ "function_simple.c")
        .addArg("--output-stdout").addArg("--mccabe-threshold=2").run;

    r.output.sliceContains(["===File", `2      `]).shouldBeTrue;
}

@(testId ~ "McCabe: shall only report functions with a McCabe value equal to or above the threshold")
unittest {
    mixin(envSetup(globalTestdir));

    auto r = makeDextool(testEnv).addInputArg(testData ~ "test_threshold.cpp")
        .addArg("--output-stdout").addArg("--mccabe-threshold=5").run;

    r.output.sliceContains(["===Function", "1      f"]).shouldBeFalse;
    r.output.sliceContains(["===Function", "3      f"]).shouldBeFalse;
    r.output.sliceContains(["===Function", "4      f"]).shouldBeFalse;
    r.output.sliceContains(["===Function", "5      f_5", "9      f_9"]).shouldBeTrue;
}

@(testId ~ "McCabe: shall report the McCabe value for class methods")
unittest {
    mixin(envSetup(globalTestdir));

    auto r = makeDextool(testEnv).addInputArg(testData ~ "test_class_methods.cpp")
        .addArg("--output-stdout").addArg("--mccabe-threshold=1").run;

    r.output.sliceContains(["===File", "7   "]).shouldBeTrue;
    // dfmt off
    // methods
    r.output.sliceContains(["===Function",
                           "1      A", // constructor
                           "1      A", // constructor
                           "1      inline_", // method
                           "1      operator bool", // conversion function
                           "1      operator=", // method
                           "1      outside", // method
                           "1      ~A", // destructor
    ]).shouldBeTrue;
    // dfmt on
}

@(testId ~ "McCabe: shall be McCabe complexity for templates")
unittest {
    mixin(envSetup(globalTestdir));

    auto r = makeDextool(testEnv).addInputArg(testData ~ "templates.cpp")
        .addArg("--output-stdout").addArg("--mccabe-threshold=0").run;

    // dfmt off
    r.output.sliceContains(["===Function",
                           "1      Class", // template class specialization
                           "1      Class<A>",
                           "1      ClassMethod",
                           "1      InnerTemplateMethod", // function template
                           "2      template_func", // function template
                           "1      ~Class<A>",
    ]).shouldBeTrue;
    // dfmt on
}

@(testId ~ "McCabe: shall be the total McCabe value of all files, ignoring threshold")
unittest {
    mixin(envSetup(globalTestdir));

    // dfmt off
    auto r = makeDextool(testEnv).addInputArg(testData ~ "templates.cpp")
        // this file only have mccabe 2 but is still counted as part of the total
        .addInputArg(testData ~ "function_simple.c")
        .addArg("--mccabe-threshold=5")
        .addArg("--output-stdout")
        .run;
    // dfmt on

    r.output.sliceContains("===Total McCabe 9").shouldBeTrue;
}

@(testId ~ "McCabe: shall deduplicate plain functions")
unittest {
    mixin(envSetup(globalTestdir));

    // dfmt off
    auto r = makeDextool(testEnv)
        .addArg("--compile-db=" ~ (testData ~ "compiledb/db_multile_occurance_same_file.json").toString)
        .addArg("--mccabe-threshold=1")
        .addArg("--output-stdout")
        .run;
    // dfmt on

    r.output.sliceContains(["===File", "1    "]).shouldBeTrue;
    r.output.sliceContains("1      one_function").shouldBeTrue;
    r.output.sliceContains(["1      one_function", "1      one_function"]).shouldBeFalse;
}

@(testId ~ "McCabe: shall _correctly_ count include's uniquely")
unittest {
    mixin(envSetup(globalTestdir));

    // dfmt off
    auto r = makeDextool(testEnv)
        .addArg("--compile-db=" ~ (testData ~ "compiledb/test_include_mccabe_counting.json").toString)
        .addArg("--mccabe-threshold=1")
        .addArg("--output-stdout")
        .run;
    // dfmt on

    r.output.sliceContains([
            "1      free_func_counted1", "1      free_func_counted2",
            "1      inline_counted"
            ]).shouldBeTrue;
}

@(
        testId
        ~ "McCabe: shall uniquely count the functions in the namespaces even though they have the same identifier")
unittest {
    mixin(envSetup(globalTestdir));

    // dfmt off
    auto r = makeDextool(testEnv)
        .addInputArg(testData ~ "same_func_name_different_namespace.cpp")
        .addArg("--mccabe-threshold=1")
        .addArg("--output-stdout")
        .run;
    // dfmt on

    r.output.sliceContains(["1     func", "1     func"]);
}
