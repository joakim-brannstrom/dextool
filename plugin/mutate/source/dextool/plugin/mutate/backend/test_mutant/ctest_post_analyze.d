/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

#SPC-track_ctest
*/
module dextool.plugin.mutate.backend.test_mutant.ctest_post_analyze;

import std.exception : collectException;
import std.range : isInputRange, isOutputRange;
import logger = std.experimental.logger;

import dextool.plugin.mutate.backend.test_mutant.interface_ : TestCaseReport,
    GatherTestCase;
import dextool.plugin.mutate.backend.type : TestCase;
import dextool.type : AbsolutePath;

/** Parse input for ctest test cases.
 *
 * Params:
 *  r = range that is chunked by line
 *  report = where the results are put.
 */
struct CtestParser {
    import std.regex : ctRegex, matchFirst;

    private {
        // example: Start 35: gtest_repeat_test
        enum re_start_tc = ctRegex!(`^\s*Start\s*\d*:\s*(?P<tc>.*)`);
        // example:  2/3  Test  #2: gmock-cardinalities_test ................***Failed    0.00 sec
        enum re_fail_tc = ctRegex!(`.*?Test.*:\s*(?P<tc>.*?)\s*\.*\*\*\*.*`);

        StateData data;
    }

    void process(T)(T line, TestCaseReport report) {
        auto start_tc_match = matchFirst(line, re_start_tc);
        auto fail_tc_match = matchFirst(line, re_fail_tc);

        data.hasStartTc = !start_tc_match.empty;
        data.hasFailTc = !fail_tc_match.empty;

        if (data.hasStartTc)
            report.reportFound(TestCase(start_tc_match["tc"].idup));

        if (data.hasFailTc)
            report.reportFailed(TestCase(fail_tc_match["tc"].idup));
    }
}

private:

struct StateData {
    bool hasStartTc;
    bool hasFailTc;
}

version (unittest) {
    import std.algorithm : each, sort;
    import std.array : array;
    import dextool.type : FileName;
    import unit_threaded : shouldEqual, shouldBeIn;
}

@("shall report the failed test cases")
unittest {
    auto app = new GatherTestCase;
    CtestParser parser;
    testData2.each!(a => parser.process(a, app));

    // dfmt off
    shouldEqual(app.failedAsArray.sort,
                [TestCase("gmock-cardinalities_test")]
                );
    // dfmt on
}

@("shall report the found test cases")
unittest {
    auto app = new GatherTestCase;
    CtestParser parser;
    testData1.each!(a => parser.process(a, app));

    // dfmt off
    shouldEqual(app.foundAsArray.sort, [
                TestCase("gmock-actions_test"),
                TestCase("gmock-cardinalities_test"),
                TestCase("gmock_ex_test")
                ]);
    // dfmt on
}

version (unittest) {
    string[] testData1() {
        // dfmt off
        return [
"Test project /home/joker/src/cpp/googletest/build",
"      Start  1: gmock-actions_test",
" 1/3  Test  #1: gmock-actions_test ......................   Passed    1.61 sec",
"      Start  2: gmock-cardinalities_test",
" 2/3  Test  #2: gmock-cardinalities_test ................   Passed    0.00 sec",
"      Start  3: gmock_ex_test",
" 3/3  Test  #3: gmock_ex_test ...........................   Passed    0.01 sec",
"",
"100% tests passed, 0 tests failed out of 3",
"",
"Total Test time (real) =   7.10 sec",
        ];
        // dfmt on
    }

    string[] testData2() {
        // dfmt off
        return [
"Test project /home/joker/src/cpp/googletest/build",
"      Start  1: gmock-actions_test",
" 1/3  Test  #1: gmock-actions_test ......................   Passed    1.61 sec",
"      Start  2: gmock-cardinalities_test",
" 2/3  Test  #2: gmock-cardinalities_test ................***Failed    0.00 sec",
"      Start  3: gmock_ex_test",
" 3/3  Test  #3: gmock_ex_test ...........................   Passed    0.01 sec",
"",
"100% tests passed, 0 tests failed out of 3",
"",
"Total Test time (real) =   7.10 sec",
"",
"The following tests FAILED:",
"         15 - gmock-cardinalities_test (Failed)",
        ];
        // dfmt on
    }
}
