/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

#SPC-plugin_mutate_track_gtest

# Design
The parser is a strict Moore FSM.
The FSM is small enough that a switch implementation is good enough, clear and explicit.

The parser has a strict separation of the *next state* and *action*.
This is to make it easier to unittest the FSM is so is needed.
It also makes it easier to understand what the state transitions are dependent on and when an action is performed.

The calculation of the next state is a strongly pure function to enforce that it is only dependent on the input. See: `nextState`.
*/
module dextool.plugin.mutate.backend.test_mutant.gtest_post_analyze;

import std.exception : collectException;
import std.range : isInputRange, isOutputRange;
import logger = std.experimental.logger;

import dextool.type : AbsolutePath;
import dextool.plugin.mutate.backend.type : TestCase;

/** Parse input for google test cases.
Params:
    r = range that is chunked by line
    sink = an output that accepts values of type TestCase via `put`.
    reldir = file paths are adjusted to be relative to this parameter.
  */
struct GtestParser {
    import std.regex : regex, ctRegex, matchFirst;

    private {
        // example: [ RUN      ] PassingTest.PassingTest1
        // example: +ull)m[ RUN      ] ADeathTest.ShouldRunFirst
        enum re_run_block = ctRegex!(`\[\s*RUN\s*\]\s`);
        // example: gtest_output_test_.cc:#: Failure
        enum re_fail_msg = ctRegex!(`^(?P<file>.*?):.*Failure`);
        // example: [  FAILED  ] NonfatalFailureTest.EscapesStringOperands
        enum re_failed_block = ctRegex!(`\[\s*FAILED\s*\]\s*(?P<tc>.*)`);

        AbsolutePath reldir;
        FsmData data;
        string fail_msg_file;
    }

    this(AbsolutePath reldir) @safe pure nothrow @nogc {
        this.reldir = reldir;
    }

    void process(T, T1)(T line, ref T1 sink) {
        import std.algorithm : until;
        import std.format : format;
        import std.range : put;
        import std.string : strip;
        import std.path : isValidPath, relativePath;

        auto fail_msg_match = matchFirst(line, re_fail_msg);
        auto failed_block_match = matchFirst(line, re_failed_block);
        data.hasRunBlock = !matchFirst(line, re_run_block).empty;
        data.hasFailedMessage = !fail_msg_match.empty;
        data.hasFailedBlock = !failed_block_match.empty;

        {
            auto rval = nextState(data);
            data.st = rval[0];
            data.act = rval[1];
        }

        final switch (data.act) with (Action) {
        case none:
            break;
        case saveFileName:
            fail_msg_file = fail_msg_match["file"].strip.idup;
            try {
                if (fail_msg_file.isValidPath)
                    fail_msg_file = relativePath(fail_msg_file, reldir);
            }
            catch (Exception e) {
                debug logger.trace(e.msg).collectException;
            }
            break;
        case putTestCase:
            // dfmt off
                put(sink, TestCase(format("%s:%s", fail_msg_file,
                                          // remove the time that googletest print.
                                          // it isn't part of the test case name but additional metadata.
                                          failed_block_match["tc"].until(' '))));
                // dfmt on
            break;
        case countLinesAfterRun:
            data.linesAfterRun += 1;
            break;
        case resetCounter:
            data.linesAfterRun = 0;
            break;
        }
    }
}

version (unittest) {
} else {
private:
}

enum State {
    findRun,
    findFailureMsg,
    findEndFailed,
}

enum Action {
    none,
    saveFileName,
    putTestCase,
    resetCounter,
    countLinesAfterRun,
}

struct FsmData {
    State st;
    Action act;

    /// The line contains a [ RUN   ] block.
    bool hasRunBlock;
    /// The line contains a <path>:line: Failure.
    bool hasFailedMessage;
    /// the line contains a [ FAILED  ] block.
    bool hasFailedBlock;
    /// the line contains a [ OK   ] block.
    bool hasOkBlock;

    /// Number of lines since a [ RUN   ] block where encountered.
    uint linesAfterRun;
}

auto nextState(immutable FsmData d) @safe pure nothrow @nogc {
    import std.typecons : tuple;

    State next = d.st;
    Action act = d.act;

    final switch (d.st) with (State) {
    case findRun:
        act = Action.resetCounter;
        if (d.hasRunBlock) {
            next = findFailureMsg;
        }
        break;
    case findFailureMsg:
        act = Action.countLinesAfterRun;

        if (d.hasFailedMessage) {
            next = findEndFailed;
            act = Action.saveFileName;
        } else if (d.linesAfterRun > 10) {
            // 10 is chosen to be somewhat resilient against junk in the output but still be conservative.
            next = findRun;
        } else if (d.hasOkBlock)
            next = findRun;
        else if (d.hasFailedBlock)
            next = findRun;
        break;
    case findEndFailed:
        act = Action.none;

        if (d.hasRunBlock)
            next = findFailureMsg;
        else if (d.hasFailedBlock) {
            act = Action.putTestCase;
            next = findRun;
        }
        break;
    }

    return tuple(next, act);
}

@("shall report the failed test case")
unittest {
    import std.array : appender;
    import std.file : getcwd;
    import dextool.type : FileName;
    import unit_threaded : shouldEqual;
    import std.algorithm : each;

    auto app = appender!(TestCase[])();
    auto reldir = AbsolutePath(FileName(getcwd));

    auto parser = GtestParser(reldir);
    testData1.each!(a => parser.process(a, app));

    shouldEqual(app.data,
            ["./googletest/test/gtest-message_test.cc:MessageTest.DefaultConstructor"]);
}

@("shall report the failed test cases even though there are junk in the output")
unittest {
    import std.array : appender;
    import std.file : getcwd;
    import dextool.type : FileName;
    import unit_threaded : shouldEqual;
    import std.algorithm : each;

    auto app = appender!(TestCase[])();
    auto reldir = AbsolutePath(FileName(getcwd));

    auto parser = GtestParser(reldir);
    testData2.each!(a => parser.process(a, app));

    // dfmt off
    shouldEqual(app.data,
            [
`gtest_output_test_.cc:NonfatalFailureTest.EscapesStringOperands`,
`gtest_output_test_.cc:NonfatalFailureTest.DiffForLongStrings`,
`gtest_output_test_.cc:FatalFailureTest.FatalFailureInSubroutine`,
`gtest_output_test_.cc:FatalFailureTest.FatalFailureInNestedSubroutine`,
`gtest_output_test_.cc:FatalFailureTest.NonfatalFailureInSubroutine`,
`gtest_output_test_.cc:LoggingTest.InterleavingLoggingAndAssertions`,
`gtest_output_test_.cc:SCOPED_TRACETest.ObeysScopes`,
`gtest_output_test_.cc:SCOPED_TRACETest.WorksInLoop`,
`gtest_output_test_.cc:SCOPED_TRACETest.WorksInSubroutine`,
`gtest_output_test_.cc:SCOPED_TRACETest.CanBeNested`,
`gtest_output_test_.cc:SCOPED_TRACETest.CanBeRepeated`,
`gtest_output_test_.cc:SCOPED_TRACETest.WorksConcurrently`,
`gtest_output_test_.cc:NonFatalFailureInFixtureConstructorTest.FailureInConstructor`,
`gtest_output_test_.cc:FatalFailureInFixtureConstructorTest.FailureInConstructor`,
`gtest_output_test_.cc:NonFatalFailureInSetUpTest.FailureInSetUp`,
`gtest_output_test_.cc:FatalFailureInSetUpTest.FailureInSetUp`,
`foo.cc:AddFailureAtTest.MessageContainsSpecifiedFileAndLineNumber`,
`gtest.cc:MixedUpTestCaseTest.ThisShouldFail`,
`gtest.cc:MixedUpTestCaseTest.ThisShouldFailToo`,
`gtest.cc:MixedUpTestCaseWithSameTestNameTest.TheSecondTestWithThisNameShouldFail`,
`gtest.cc:TEST_F_before_TEST_in_same_test_case.DefinedUsingTESTAndShouldFail`,
`gtest.cc:TEST_before_TEST_F_in_same_test_case.DefinedUsingTEST_FAndShouldFail`,
`gtest.cc:ExpectNonfatalFailureTest.FailsWhenThereIsNoNonfatalFailure`,
`gtest.cc:ExpectNonfatalFailureTest.FailsWhenThereAreTwoNonfatalFailures`,
`gtest.cc:ExpectNonfatalFailureTest.FailsWhenThereIsOneFatalFailure`,
`gtest.cc:ExpectNonfatalFailureTest.FailsWhenStatementReturns`,
`gtest.cc:ExpectNonfatalFailureTest.FailsWhenStatementThrows`,
`gtest.cc:ExpectFatalFailureTest.FailsWhenThereIsNoFatalFailure`,
`gtest.cc:ExpectFatalFailureTest.FailsWhenThereAreTwoFatalFailures`,
`gtest.cc:ExpectFatalFailureTest.FailsWhenThereIsOneNonfatalFailure`,
`gtest.cc:ExpectFatalFailureTest.FailsWhenStatementReturns`,
`gtest.cc:ExpectFatalFailureTest.FailsWhenStatementThrows`,
`gtest_output_test_.cc:TypedTest/0.Failure,`,
`gtest_output_test_.cc:Unsigned/TypedTestP/0.Failure,`,
`gtest_output_test_.cc:Unsigned/TypedTestP/1.Failure,`,
`gtest.cc:ExpectFailureTest.ExpectFatalFailure`,
`gtest.cc:ExpectFailureTest.ExpectNonFatalFailure`,
`gtest.cc:ExpectFailureTest.ExpectFatalFailureOnAllThreads`,
`gtest.cc:ExpectFailureTest.ExpectNonFatalFailureOnAllThreads`,
`gtest_output_test_.cc:ExpectFailureWithThreadsTest.ExpectFatalFailure`,
`gtest_output_test_.cc:ExpectFailureWithThreadsTest.ExpectNonFatalFailure`,
`gtest_output_test_.cc:ScopedFakeTestPartResultReporterTest.InterceptOnlyCurrentThread`,
`gtest_output_test_.cc:PrintingFailingParams/FailingParamTest.Fails/0,`,
`gtest_output_test_.cc:PrintingStrings/ParamTest.Failure/a,`,
            ]);
    // dfmt on
}

version (unittest) {
    // dfmt off
    string[] testData1() {
        return [
"Running main() from gtest_main.cc",
"[==========] Running 17 tests from 1 test case.",
"[----------] Global test environment set-up.",
"[----------] 17 tests from MessageTest",
"[ RUN      ] MessageTest.DefaultConstructor",
"./googletest/test/gtest-message_test.cc:48: Failure",
"Expected equality of these values:",
"  true",
"  false",
"[  FAILED  ] MessageTest.DefaultConstructor (0 ms)",
"[ RUN      ] MessageTest.CopyConstructor",
"[       OK ] MessageTest.CopyConstructor (0 ms)",
"[ RUN      ] MessageTest.ConstructsFromCString",
"[       OK ] MessageTest.ConstructsFromCString (0 ms)",
"[----------] 3 tests from MessageTest (0 ms total)",
"",
"[----------] Global test environment tear-down",
"[==========] 3 tests from 1 test case ran. (0 ms total)",
"[  PASSED  ] 2 tests.",
"[  FAILED  ] 1 test, listed below:",
"[  FAILED  ] MessageTest.DefaultConstructor",
"",
" 1 FAILED TEST",
        ];
}

    // Example data from the "wild" that should still parse
    string[] testData2() {
        return [
`-[==========] Running 66 tests from 29 test cases.`,
`-[----------] Global test environment set-up.`,
`+ull)m[==========] Running 66 tests from 29 test cases.`,
`+ull)m[----------] Global test environment set-up.`,
` FooEnvironment::SetUp() called.`,
` BarEnvironment::SetUp() called.`,
`-[----------] 1 test from ADeathTest`,
`-[ RUN      ] ADeathTest.ShouldRunFirst`,
`-[       OK ] ADeathTest.ShouldRunFirst`,
`-[----------] 1 test from ATypedDeathTest/0, where TypeParam = int`,
`-[ RUN      ] ATypedDeathTest/0.ShouldRunFirst`,
`-[       OK ] ATypedDeathTest/0.ShouldRunFirst`,
`-[----------] 1 test from ATypedDeathTest/1, where TypeParam = double`,
`-[ RUN      ] ATypedDeathTest/1.ShouldRunFirst`,
`-[       OK ] ATypedDeathTest/1.ShouldRunFirst`,
`-[----------] 1 test from My/ATypeParamDeathTest/0, where TypeParam = int`,
`-[ RUN      ] My/ATypeParamDeathTest/0.ShouldRunFirst`,
`-[       OK ] My/ATypeParamDeathTest/0.ShouldRunFirst`,
`-[----------] 1 test from My/ATypeParamDeathTest/1, where TypeParam = double`,
`-[ RUN      ] My/ATypeParamDeathTest/1.ShouldRunFirst`,
`-[       OK ] My/ATypeParamDeathTest/1.ShouldRunFirst`,
`-[----------] 2 tests from PassingTest`,
`-[ RUN      ] PassingTest.PassingTest1`,
`-[       OK ] PassingTest.PassingTest1`,
`-[ RUN      ] PassingTest.PassingTest2`,
`-[       OK ] PassingTest.PassingTest2`,
`-[----------] 2 tests from NonfatalFailureTest`,
`-[ RUN      ] NonfatalFailureTest.EscapesStringOperands`,
`+ull)m[----------] 1 test from ADeathTest`,
`+ull)m[ RUN      ] ADeathTest.ShouldRunFirst`,
`+ull)m[       OK ] ADeathTest.ShouldRunFirst`,
`+ull)m[----------] 1 test from ATypedDeathTest/0, where TypeParam = int`,
`+ull)m[ RUN      ] ATypedDeathTest/0.ShouldRunFirst`,
`+ull)m[       OK ] ATypedDeathTest/0.ShouldRunFirst`,
`+ull)m[----------] 1 test from ATypedDeathTest/1, where TypeParam = double`,
`+ull)m[ RUN      ] ATypedDeathTest/1.ShouldRunFirst`,
`+ull)m[       OK ] ATypedDeathTest/1.ShouldRunFirst`,
`+ull)m[----------] 1 test from My/ATypeParamDeathTest/0, where TypeParam = int`,
`+ull)m[ RUN      ] My/ATypeParamDeathTest/0.ShouldRunFirst`,
`+ull)m[       OK ] My/ATypeParamDeathTest/0.ShouldRunFirst`,
`+ull)m[----------] 1 test from My/ATypeParamDeathTest/1, where TypeParam = double`,
`+ull)m[ RUN      ] My/ATypeParamDeathTest/1.ShouldRunFirst`,
`+ull)m[       OK ] My/ATypeParamDeathTest/1.ShouldRunFirst`,
`+ull)m[----------] 2 tests from PassingTest`,
`+ull)m[ RUN      ] PassingTest.PassingTest1`,
`+ull)m[       OK ] PassingTest.PassingTest1`,
`+ull)m[ RUN      ] PassingTest.PassingTest2`,
`+ull)m[       OK ] PassingTest.PassingTest2`,
`+ull)m[----------] 2 tests from NonfatalFailureTest`,
`+ull)m[ RUN      ] NonfatalFailureTest.EscapesStringOperands`,
` gtest_output_test_.cc:#: Failure`,
` Expected equality of these values:`,
`   kGoldenString`,
`@@ -47,7 +47,7 @@`,
``,
`   actual`,
`     Which is: "actual \"string\""`,
` [  FAILED  ] NonfatalFailureTest.EscapesStringOperands`,
`-[ RUN      ] NonfatalFailureTest.DiffForLongStrings`,
`+ull)m[ RUN      ] NonfatalFailureTest.DiffForLongStrings`,
` gtest_output_test_.cc:#: Failure`,
` Expected equality of these values:`,
`   golden_str`,
`@@ -59,8 +59,8 @@`,
``,
`  Line 2`,
``,
` [  FAILED  ] NonfatalFailureTest.DiffForLongStrings`,
`-[----------] 3 tests from FatalFailureTest`,
`-[ RUN      ] FatalFailureTest.FatalFailureInSubroutine`,
`+ull)m[----------] 3 tests from FatalFailureTest`,
`+ull)m[ RUN      ] FatalFailureTest.FatalFailureInSubroutine`,
` (expecting a failure that x should be 1)`,
` gtest_output_test_.cc:#: Failure`,
` Expected equality of these values:`,
`@@ -68,7 +68,7 @@`,
``,
`   x`,
`     Which is: 2`,
` [  FAILED  ] FatalFailureTest.FatalFailureInSubroutine`,
`-[ RUN      ] FatalFailureTest.FatalFailureInNestedSubroutine`,
`+ull)m[ RUN      ] FatalFailureTest.FatalFailureInNestedSubroutine`,
` (expecting a failure that x should be 1)`,
` gtest_output_test_.cc:#: Failure`,
` Expected equality of these values:`,
`@@ -76,15 +76,15 @@`,
``,
`   x`,
`     Which is: 2`,
` [  FAILED  ] FatalFailureTest.FatalFailureInNestedSubroutine`,
`-[ RUN      ] FatalFailureTest.NonfatalFailureInSubroutine`,
`+ull)m[ RUN      ] FatalFailureTest.NonfatalFailureInSubroutine`,
` (expecting a failure on false)`,
` gtest_output_test_.cc:#: Failure`,
` Value of: false`,
`   Actual: false`,
` Expected: true`,
` [  FAILED  ] FatalFailureTest.NonfatalFailureInSubroutine`,
`-[----------] 1 test from LoggingTest`,
`-[ RUN      ] LoggingTest.InterleavingLoggingAndAssertions`,
`+ull)m[----------] 1 test from LoggingTest`,
`+ull)m[ RUN      ] LoggingTest.InterleavingLoggingAndAssertions`,
` (expecting 2 failures on (3) >= (a[i]))`,
` i == 0`,
` i == 1`,
`@@ -95,8 +95,8 @@`,
``,
` gtest_output_test_.cc:#: Failure`,
` Expected: (3) >= (a[i]), actual: 3 vs 6`,
` [  FAILED  ] LoggingTest.InterleavingLoggingAndAssertions`,
`-[----------] 6 tests from SCOPED_TRACETest`,
`-[ RUN      ] SCOPED_TRACETest.ObeysScopes`,
`+ull)m[----------] 6 tests from SCOPED_TRACETest`,
`+ull)m[ RUN      ] SCOPED_TRACETest.ObeysScopes`,
` (expected to fail)`,
` gtest_output_test_.cc:#: Failure`,
` Failed`,
`@@ -110,7 +110,7 @@`,
``,
` Failed`,
` This failure is expected, and shouldn't have a trace.`,
` [  FAILED  ] SCOPED_TRACETest.ObeysScopes`,
`-[ RUN      ] SCOPED_TRACETest.WorksInLoop`,
`+ull)m[ RUN      ] SCOPED_TRACETest.WorksInLoop`,
` (expected to fail)`,
` gtest_output_test_.cc:#: Failure`,
` Expected equality of these values:`,
`@@ -127,7 +127,7 @@`,
``,
` Google Test trace:`,
` gtest_output_test_.cc:#: i = 2`,
` [  FAILED  ] SCOPED_TRACETest.WorksInLoop`,
`-[ RUN      ] SCOPED_TRACETest.WorksInSubroutine`,
`+ull)m[ RUN      ] SCOPED_TRACETest.WorksInSubroutine`,
` (expected to fail)`,
` gtest_output_test_.cc:#: Failure`,
` Expected equality of these values:`,
`@@ -144,7 +144,7 @@`,
``,
` Google Test trace:`,
` gtest_output_test_.cc:#: n = 2`,
` [  FAILED  ] SCOPED_TRACETest.WorksInSubroutine`,
`-[ RUN      ] SCOPED_TRACETest.CanBeNested`,
`+ull)m[ RUN      ] SCOPED_TRACETest.CanBeNested`,
` (expected to fail)`,
` gtest_output_test_.cc:#: Failure`,
` Expected equality of these values:`,
`@@ -155,7 +155,7 @@`,
``,
` gtest_output_test_.cc:#: n = 2`,
` gtest_output_test_.cc:#:`,
` [  FAILED  ] SCOPED_TRACETest.CanBeNested`,
`-[ RUN      ] SCOPED_TRACETest.CanBeRepeated`,
`+ull)m[ RUN      ] SCOPED_TRACETest.CanBeRepeated`,
` (expected to fail)`,
` gtest_output_test_.cc:#: Failure`,
` Failed`,
`@@ -183,7 +183,7 @@`,
``,
` gtest_output_test_.cc:#: B`,
` gtest_output_test_.cc:#: A`,
` [  FAILED  ] SCOPED_TRACETest.CanBeRepeated`,
`-[ RUN      ] SCOPED_TRACETest.WorksConcurrently`,
`+ull)m[ RUN      ] SCOPED_TRACETest.WorksConcurrently`,
` (expecting 6 failures)`,
` gtest_output_test_.cc:#: Failure`,
` Failed`,
`@@ -212,8 +212,8 @@`,
``,
` Failed`,
` Expected failure #6 (in thread A, no trace alive).`,
` [  FAILED  ] SCOPED_TRACETest.WorksConcurrently`,
`-[----------] 1 test from NonFatalFailureInFixtureConstructorTest`,
`-[ RUN      ] NonFatalFailureInFixtureConstructorTest.FailureInConstructor`,
`+ull)m[----------] 1 test from NonFatalFailureInFixtureConstructorTest`,
`+ull)m[ RUN      ] NonFatalFailureInFixtureConstructorTest.FailureInConstructor`,
` (expecting 5 failures)`,
` gtest_output_test_.cc:#: Failure`,
` Failed`,
`@@ -231,8 +231,8 @@`,
``,
` Failed`,
` Expected failure #5, in the test fixture d'tor.`,
` [  FAILED  ] NonFatalFailureInFixtureConstructorTest.FailureInConstructor`,
`-[----------] 1 test from FatalFailureInFixtureConstructorTest`,
`-[ RUN      ] FatalFailureInFixtureConstructorTest.FailureInConstructor`,
`+ull)m[----------] 1 test from FatalFailureInFixtureConstructorTest`,
`+ull)m[ RUN      ] FatalFailureInFixtureConstructorTest.FailureInConstructor`,
` (expecting 2 failures)`,
` gtest_output_test_.cc:#: Failure`,
` Failed`,
`@@ -241,8 +241,8 @@`,
``,
` Failed`,
` Expected failure #2, in the test fixture d'tor.`,
` [  FAILED  ] FatalFailureInFixtureConstructorTest.FailureInConstructor`,
`-[----------] 1 test from NonFatalFailureInSetUpTest`,
`-[ RUN      ] NonFatalFailureInSetUpTest.FailureInSetUp`,
`+ull)m[----------] 1 test from NonFatalFailureInSetUpTest`,
`+ull)m[ RUN      ] NonFatalFailureInSetUpTest.FailureInSetUp`,
` (expecting 4 failures)`,
` gtest_output_test_.cc:#: Failure`,
` Failed`,
`@@ -257,8 +257,8 @@`,
``,
` Failed`,
` Expected failure #4, in the test fixture d'tor.`,
` [  FAILED  ] NonFatalFailureInSetUpTest.FailureInSetUp`,
`-[----------] 1 test from FatalFailureInSetUpTest`,
`-[ RUN      ] FatalFailureInSetUpTest.FailureInSetUp`,
`+ull)m[----------] 1 test from FatalFailureInSetUpTest`,
`+ull)m[ RUN      ] FatalFailureInSetUpTest.FailureInSetUp`,
` (expecting 3 failures)`,
` gtest_output_test_.cc:#: Failure`,
` Failed`,
`@@ -270,18 +270,18 @@`,
``,
` Failed`,
` Expected failure #3, in the test fixture d'tor.`,
` [  FAILED  ] FatalFailureInSetUpTest.FailureInSetUp`,
`-[----------] 1 test from AddFailureAtTest`,
`-[ RUN      ] AddFailureAtTest.MessageContainsSpecifiedFileAndLineNumber`,
`+ull)m[----------] 1 test from AddFailureAtTest`,
`+ull)m[ RUN      ] AddFailureAtTest.MessageContainsSpecifiedFileAndLineNumber`,
` foo.cc:42: Failure`,
` Failed`,
` Expected failure in foo.cc`,
` [  FAILED  ] AddFailureAtTest.MessageContainsSpecifiedFileAndLineNumber`,
`-[----------] 4 tests from MixedUpTestCaseTest`,
`-[ RUN      ] MixedUpTestCaseTest.FirstTestFromNamespaceFoo`,
`-[       OK ] MixedUpTestCaseTest.FirstTestFromNamespaceFoo`,
`-[ RUN      ] MixedUpTestCaseTest.SecondTestFromNamespaceFoo`,
`-[       OK ] MixedUpTestCaseTest.SecondTestFromNamespaceFoo`,
`-[ RUN      ] MixedUpTestCaseTest.ThisShouldFail`,
`+ull)m[----------] 4 tests from MixedUpTestCaseTest`,
`+ull)m[ RUN      ] MixedUpTestCaseTest.FirstTestFromNamespaceFoo`,
`+ull)m[       OK ] MixedUpTestCaseTest.FirstTestFromNamespaceFoo`,
`+ull)m[ RUN      ] MixedUpTestCaseTest.SecondTestFromNamespaceFoo`,
`+ull)m[       OK ] MixedUpTestCaseTest.SecondTestFromNamespaceFoo`,
`+ull)m[ RUN      ] MixedUpTestCaseTest.ThisShouldFail`,
` gtest.cc:#: Failure`,
` Failed`,
` All tests in the same test case must use the same test fixture`,
`@@ -292,7 +292,7 @@`,
``,
` units and have the same name.  You should probably rename one`,
` of the classes to put the tests into different test cases.`,
` [  FAILED  ] MixedUpTestCaseTest.ThisShouldFail`,
`-[ RUN      ] MixedUpTestCaseTest.ThisShouldFailToo`,
`+ull)m[ RUN      ] MixedUpTestCaseTest.ThisShouldFailToo`,
` gtest.cc:#: Failure`,
` Failed`,
` All tests in the same test case must use the same test fixture`,
`@@ -303,10 +303,10 @@`,
``,
` units and have the same name.  You should probably rename one`,
` of the classes to put the tests into different test cases.`,
` [  FAILED  ] MixedUpTestCaseTest.ThisShouldFailToo`,
`-[----------] 2 tests from MixedUpTestCaseWithSameTestNameTest`,
`-[ RUN      ] MixedUpTestCaseWithSameTestNameTest.TheSecondTestWithThisNameShouldFail`,
`-[       OK ] MixedUpTestCaseWithSameTestNameTest.TheSecondTestWithThisNameShouldFail`,
`-[ RUN      ] MixedUpTestCaseWithSameTestNameTest.TheSecondTestWithThisNameShouldFail`,
`+ull)m[----------] 2 tests from MixedUpTestCaseWithSameTestNameTest`,
`+ull)m[ RUN      ] MixedUpTestCaseWithSameTestNameTest.TheSecondTestWithThisNameShouldFail`,
`+ull)m[       OK ] MixedUpTestCaseWithSameTestNameTest.TheSecondTestWithThisNameShouldFail`,
`+ull)m[ RUN      ] MixedUpTestCaseWithSameTestNameTest.TheSecondTestWithThisNameShouldFail`,
` gtest.cc:#: Failure`,
` Failed`,
` All tests in the same test case must use the same test fixture`,
`@@ -317,10 +317,10 @@`,
``,
` units and have the same name.  You should probably rename one`,
` of the classes to put the tests into different test cases.`,
` [  FAILED  ] MixedUpTestCaseWithSameTestNameTest.TheSecondTestWithThisNameShouldFail`,
`-[----------] 2 tests from TEST_F_before_TEST_in_same_test_case`,
`-[ RUN      ] TEST_F_before_TEST_in_same_test_case.DefinedUsingTEST_F`,
`-[       OK ] TEST_F_before_TEST_in_same_test_case.DefinedUsingTEST_F`,
`-[ RUN      ] TEST_F_before_TEST_in_same_test_case.DefinedUsingTESTAndShouldFail`,
`+ull)m[----------] 2 tests from TEST_F_before_TEST_in_same_test_case`,
`+ull)m[ RUN      ] TEST_F_before_TEST_in_same_test_case.DefinedUsingTEST_F`,
`+ull)m[       OK ] TEST_F_before_TEST_in_same_test_case.DefinedUsingTEST_F`,
`+ull)m[ RUN      ] TEST_F_before_TEST_in_same_test_case.DefinedUsingTESTAndShouldFail`,
` gtest.cc:#: Failure`,
` Failed`,
` All tests in the same test case must use the same test fixture`,
`@@ -331,10 +331,10 @@`,
``,
` want to change the TEST to TEST_F or move it to another test`,
` case.`,
` [  FAILED  ] TEST_F_before_TEST_in_same_test_case.DefinedUsingTESTAndShouldFail`,
`-[----------] 2 tests from TEST_before_TEST_F_in_same_test_case`,
`-[ RUN      ] TEST_before_TEST_F_in_same_test_case.DefinedUsingTEST`,
`-[       OK ] TEST_before_TEST_F_in_same_test_case.DefinedUsingTEST`,
`-[ RUN      ] TEST_before_TEST_F_in_same_test_case.DefinedUsingTEST_FAndShouldFail`,
`+ull)m[----------] 2 tests from TEST_before_TEST_F_in_same_test_case`,
`+ull)m[ RUN      ] TEST_before_TEST_F_in_same_test_case.DefinedUsingTEST`,
`+ull)m[       OK ] TEST_before_TEST_F_in_same_test_case.DefinedUsingTEST`,
`+ull)m[ RUN      ] TEST_before_TEST_F_in_same_test_case.DefinedUsingTEST_FAndShouldFail`,
` gtest.cc:#: Failure`,
` Failed`,
` All tests in the same test case must use the same test fixture`,
`@@ -345,20 +345,20 @@`,
``,
` want to change the TEST to TEST_F or move it to another test`,
` case.`,
` [  FAILED  ] TEST_before_TEST_F_in_same_test_case.DefinedUsingTEST_FAndShouldFail`,
`-[----------] 8 tests from ExpectNonfatalFailureTest`,
`-[ RUN      ] ExpectNonfatalFailureTest.CanReferenceGlobalVariables`,
`-[       OK ] ExpectNonfatalFailureTest.CanReferenceGlobalVariables`,
`-[ RUN      ] ExpectNonfatalFailureTest.CanReferenceLocalVariables`,
`-[       OK ] ExpectNonfatalFailureTest.CanReferenceLocalVariables`,
`-[ RUN      ] ExpectNonfatalFailureTest.SucceedsWhenThereIsOneNonfatalFailure`,
`-[       OK ] ExpectNonfatalFailureTest.SucceedsWhenThereIsOneNonfatalFailure`,
`-[ RUN      ] ExpectNonfatalFailureTest.FailsWhenThereIsNoNonfatalFailure`,
`+ull)m[----------] 8 tests from ExpectNonfatalFailureTest`,
`+ull)m[ RUN      ] ExpectNonfatalFailureTest.CanReferenceGlobalVariables`,
`+ull)m[       OK ] ExpectNonfatalFailureTest.CanReferenceGlobalVariables`,
`+ull)m[ RUN      ] ExpectNonfatalFailureTest.CanReferenceLocalVariables`,
`+ull)m[       OK ] ExpectNonfatalFailureTest.CanReferenceLocalVariables`,
`+ull)m[ RUN      ] ExpectNonfatalFailureTest.SucceedsWhenThereIsOneNonfatalFailure`,
`+ull)m[       OK ] ExpectNonfatalFailureTest.SucceedsWhenThereIsOneNonfatalFailure`,
`+ull)m[ RUN      ] ExpectNonfatalFailureTest.FailsWhenThereIsNoNonfatalFailure`,
` (expecting a failure)`,
` gtest.cc:#: Failure`,
` Expected: 1 non-fatal failure`,
`   Actual: 0 failures`,
` [  FAILED  ] ExpectNonfatalFailureTest.FailsWhenThereIsNoNonfatalFailure`,
`-[ RUN      ] ExpectNonfatalFailureTest.FailsWhenThereAreTwoNonfatalFailures`,
`+ull)m[ RUN      ] ExpectNonfatalFailureTest.FailsWhenThereAreTwoNonfatalFailures`,
` (expecting a failure)`,
` gtest.cc:#: Failure`,
` Expected: 1 non-fatal failure`,
`@@ -372,7 +372,7 @@`,
``,
` Expected non-fatal failure 2.`,
``,
` [  FAILED  ] ExpectNonfatalFailureTest.FailsWhenThereAreTwoNonfatalFailures`,
`-[ RUN      ] ExpectNonfatalFailureTest.FailsWhenThereIsOneFatalFailure`,
`+ull)m[ RUN      ] ExpectNonfatalFailureTest.FailsWhenThereIsOneFatalFailure`,
` (expecting a failure)`,
` gtest.cc:#: Failure`,
` Expected: 1 non-fatal failure`,
`@@ -382,32 +382,32 @@`,
``,
` Expected fatal failure.`,
``,
` [  FAILED  ] ExpectNonfatalFailureTest.FailsWhenThereIsOneFatalFailure`,
`-[ RUN      ] ExpectNonfatalFailureTest.FailsWhenStatementReturns`,
`+ull)m[ RUN      ] ExpectNonfatalFailureTest.FailsWhenStatementReturns`,
` (expecting a failure)`,
` gtest.cc:#: Failure`,
` Expected: 1 non-fatal failure`,
`   Actual: 0 failures`,
` [  FAILED  ] ExpectNonfatalFailureTest.FailsWhenStatementReturns`,
`-[ RUN      ] ExpectNonfatalFailureTest.FailsWhenStatementThrows`,
`+ull)m[ RUN      ] ExpectNonfatalFailureTest.FailsWhenStatementThrows`,
` (expecting a failure)`,
` gtest.cc:#: Failure`,
` Expected: 1 non-fatal failure`,
`   Actual: 0 failures`,
` [  FAILED  ] ExpectNonfatalFailureTest.FailsWhenStatementThrows`,
`-[----------] 8 tests from ExpectFatalFailureTest`,
`-[ RUN      ] ExpectFatalFailureTest.CanReferenceGlobalVariables`,
`-[       OK ] ExpectFatalFailureTest.CanReferenceGlobalVariables`,
`-[ RUN      ] ExpectFatalFailureTest.CanReferenceLocalStaticVariables`,
`-[       OK ] ExpectFatalFailureTest.CanReferenceLocalStaticVariables`,
`-[ RUN      ] ExpectFatalFailureTest.SucceedsWhenThereIsOneFatalFailure`,
`-[       OK ] ExpectFatalFailureTest.SucceedsWhenThereIsOneFatalFailure`,
`-[ RUN      ] ExpectFatalFailureTest.FailsWhenThereIsNoFatalFailure`,
`+ull)m[----------] 8 tests from ExpectFatalFailureTest`,
`+ull)m[ RUN      ] ExpectFatalFailureTest.CanReferenceGlobalVariables`,
`+ull)m[       OK ] ExpectFatalFailureTest.CanReferenceGlobalVariables`,
`+ull)m[ RUN      ] ExpectFatalFailureTest.CanReferenceLocalStaticVariables`,
`+ull)m[       OK ] ExpectFatalFailureTest.CanReferenceLocalStaticVariables`,
`+ull)m[ RUN      ] ExpectFatalFailureTest.SucceedsWhenThereIsOneFatalFailure`,
`+ull)m[       OK ] ExpectFatalFailureTest.SucceedsWhenThereIsOneFatalFailure`,
`+ull)m[ RUN      ] ExpectFatalFailureTest.FailsWhenThereIsNoFatalFailure`,
` (expecting a failure)`,
` gtest.cc:#: Failure`,
` Expected: 1 fatal failure`,
`   Actual: 0 failures`,
` [  FAILED  ] ExpectFatalFailureTest.FailsWhenThereIsNoFatalFailure`,
`-[ RUN      ] ExpectFatalFailureTest.FailsWhenThereAreTwoFatalFailures`,
`+ull)m[ RUN      ] ExpectFatalFailureTest.FailsWhenThereAreTwoFatalFailures`,
` (expecting a failure)`,
` gtest.cc:#: Failure`,
` Expected: 1 fatal failure`,
`@@ -421,7 +421,7 @@`,
``,
` Expected fatal failure.`,
``,
` [  FAILED  ] ExpectFatalFailureTest.FailsWhenThereAreTwoFatalFailures`,
`-[ RUN      ] ExpectFatalFailureTest.FailsWhenThereIsOneNonfatalFailure`,
`+ull)m[ RUN      ] ExpectFatalFailureTest.FailsWhenThereIsOneNonfatalFailure`,
` (expecting a failure)`,
` gtest.cc:#: Failure`,
` Expected: 1 fatal failure`,
`@@ -431,22 +431,22 @@`,
``,
` Expected non-fatal failure.`,
``,
` [  FAILED  ] ExpectFatalFailureTest.FailsWhenThereIsOneNonfatalFailure`,
`-[ RUN      ] ExpectFatalFailureTest.FailsWhenStatementReturns`,
`+ull)m[ RUN      ] ExpectFatalFailureTest.FailsWhenStatementReturns`,
` (expecting a failure)`,
` gtest.cc:#: Failure`,
` Expected: 1 fatal failure`,
`   Actual: 0 failures`,
` [  FAILED  ] ExpectFatalFailureTest.FailsWhenStatementReturns`,
`-[ RUN      ] ExpectFatalFailureTest.FailsWhenStatementThrows`,
`+ull)m[ RUN      ] ExpectFatalFailureTest.FailsWhenStatementThrows`,
` (expecting a failure)`,
` gtest.cc:#: Failure`,
` Expected: 1 fatal failure`,
`   Actual: 0 failures`,
` [  FAILED  ] ExpectFatalFailureTest.FailsWhenStatementThrows`,
`-[----------] 2 tests from TypedTest/0, where TypeParam = int`,
`-[ RUN      ] TypedTest/0.Success`,
`-[       OK ] TypedTest/0.Success`,
`-[ RUN      ] TypedTest/0.Failure`,
`+ull)m[----------] 2 tests from TypedTest/0, where TypeParam = int`,
`+ull)m[ RUN      ] TypedTest/0.Success`,
`+ull)m[       OK ] TypedTest/0.Success`,
`+ull)m[ RUN      ] TypedTest/0.Failure`,
` gtest_output_test_.cc:#: Failure`,
` Expected equality of these values:`,
`   1`,
`@@ -454,10 +454,10 @@`,
``,
`     Which is: 0`,
` Expected failure`,
` [  FAILED  ] TypedTest/0.Failure, where TypeParam = int`,
`-[----------] 2 tests from Unsigned/TypedTestP/0, where TypeParam = unsigned char`,
`-[ RUN      ] Unsigned/TypedTestP/0.Success`,
`-[       OK ] Unsigned/TypedTestP/0.Success`,
`-[ RUN      ] Unsigned/TypedTestP/0.Failure`,
`+ull)m[----------] 2 tests from Unsigned/TypedTestP/0, where TypeParam = unsigned char`,
`+ull)m[ RUN      ] Unsigned/TypedTestP/0.Success`,
`+ull)m[       OK ] Unsigned/TypedTestP/0.Success`,
`+ull)m[ RUN      ] Unsigned/TypedTestP/0.Failure`,
` gtest_output_test_.cc:#: Failure`,
` Expected equality of these values:`,
`   1U`,
`@@ -466,10 +466,10 @@`,
``,
`     Which is: '\0'`,
` Expected failure`,
` [  FAILED  ] Unsigned/TypedTestP/0.Failure, where TypeParam = unsigned char`,
`-[----------] 2 tests from Unsigned/TypedTestP/1, where TypeParam = unsigned`,
`-[ RUN      ] Unsigned/TypedTestP/1.Success`,
`-[       OK ] Unsigned/TypedTestP/1.Success`,
`-[ RUN      ] Unsigned/TypedTestP/1.Failure`,
`+ull)m[----------] 2 tests from Unsigned/TypedTestP/1, where TypeParam = unsigned`,
`+ull)m[ RUN      ] Unsigned/TypedTestP/1.Success`,
`+ull)m[       OK ] Unsigned/TypedTestP/1.Success`,
`+ull)m[ RUN      ] Unsigned/TypedTestP/1.Failure`,
` gtest_output_test_.cc:#: Failure`,
` Expected equality of these values:`,
`   1U`,
`@@ -478,8 +478,8 @@`,
``,
`     Which is: 0`,
` Expected failure`,
` [  FAILED  ] Unsigned/TypedTestP/1.Failure, where TypeParam = unsigned`,
`-[----------] 4 tests from ExpectFailureTest`,
`-[ RUN      ] ExpectFailureTest.ExpectFatalFailure`,
`+ull)m[----------] 4 tests from ExpectFailureTest`,
`+ull)m[ RUN      ] ExpectFailureTest.ExpectFatalFailure`,
` (expecting 1 failure)`,
` gtest.cc:#: Failure`,
` Expected: 1 fatal failure`,
`@@ -504,7 +504,7 @@`,
``,
` Expected fatal failure.`,
``,
` [  FAILED  ] ExpectFailureTest.ExpectFatalFailure`,
`-[ RUN      ] ExpectFailureTest.ExpectNonFatalFailure`,
`+ull)m[ RUN      ] ExpectFailureTest.ExpectNonFatalFailure`,
` (expecting 1 failure)`,
` gtest.cc:#: Failure`,
` Expected: 1 non-fatal failure`,
`@@ -529,7 +529,7 @@`,
``,
` Expected non-fatal failure.`,
``,
` [  FAILED  ] ExpectFailureTest.ExpectNonFatalFailure`,
`-[ RUN      ] ExpectFailureTest.ExpectFatalFailureOnAllThreads`,
`+ull)m[ RUN      ] ExpectFailureTest.ExpectFatalFailureOnAllThreads`,
` (expecting 1 failure)`,
` gtest.cc:#: Failure`,
` Expected: 1 fatal failure`,
`@@ -554,7 +554,7 @@`,
``,
` Expected fatal failure.`,
``,
` [  FAILED  ] ExpectFailureTest.ExpectFatalFailureOnAllThreads`,
`-[ RUN      ] ExpectFailureTest.ExpectNonFatalFailureOnAllThreads`,
`+ull)m[ RUN      ] ExpectFailureTest.ExpectNonFatalFailureOnAllThreads`,
` (expecting 1 failure)`,
` gtest.cc:#: Failure`,
` Expected: 1 non-fatal failure`,
`@@ -579,8 +579,8 @@`,
``,
` Expected non-fatal failure.`,
``,
` [  FAILED  ] ExpectFailureTest.ExpectNonFatalFailureOnAllThreads`,
`-[----------] 2 tests from ExpectFailureWithThreadsTest`,
`-[ RUN      ] ExpectFailureWithThreadsTest.ExpectFatalFailure`,
`+ull)m[----------] 2 tests from ExpectFailureWithThreadsTest`,
`+ull)m[ RUN      ] ExpectFailureWithThreadsTest.ExpectFatalFailure`,
` (expecting 2 failures)`,
` gtest_output_test_.cc:#: Failure`,
` Failed`,
`@@ -589,7 +589,7 @@`,
``,
` Expected: 1 fatal failure`,
`   Actual: 0 failures`,
` [  FAILED  ] ExpectFailureWithThreadsTest.ExpectFatalFailure`,
`-[ RUN      ] ExpectFailureWithThreadsTest.ExpectNonFatalFailure`,
`+ull)m[ RUN      ] ExpectFailureWithThreadsTest.ExpectNonFatalFailure`,
` (expecting 2 failures)`,
` gtest_output_test_.cc:#: Failure`,
` Failed`,
`@@ -598,8 +598,8 @@`,
``,
` Expected: 1 non-fatal failure`,
`   Actual: 0 failures`,
` [  FAILED  ] ExpectFailureWithThreadsTest.ExpectNonFatalFailure`,
`-[----------] 1 test from ScopedFakeTestPartResultReporterTest`,
`-[ RUN      ] ScopedFakeTestPartResultReporterTest.InterceptOnlyCurrentThread`,
`+ull)m[----------] 1 test from ScopedFakeTestPartResultReporterTest`,
`+ull)m[ RUN      ] ScopedFakeTestPartResultReporterTest.InterceptOnlyCurrentThread`,
` (expecting 2 failures)`,
` gtest_output_test_.cc:#: Failure`,
` Failed`,
`@@ -608,18 +608,18 @@`,
``,
` Failed`,
` Expected non-fatal failure.`,
` [  FAILED  ] ScopedFakeTestPartResultReporterTest.InterceptOnlyCurrentThread`,
`-[----------] 1 test from PrintingFailingParams/FailingParamTest`,
`-[ RUN      ] PrintingFailingParams/FailingParamTest.Fails/0`,
`+ull)m[----------] 1 test from PrintingFailingParams/FailingParamTest`,
`+ull)m[ RUN      ] PrintingFailingParams/FailingParamTest.Fails/0`,
` gtest_output_test_.cc:#: Failure`,
` Expected equality of these values:`,
`   1`,
`   GetParam()`,
`     Which is: 2`,
` [  FAILED  ] PrintingFailingParams/FailingParamTest.Fails/0, where GetParam() = 2`,
`-[----------] 2 tests from PrintingStrings/ParamTest`,
`-[ RUN      ] PrintingStrings/ParamTest.Success/a`,
`-[       OK ] PrintingStrings/ParamTest.Success/a`,
`-[ RUN      ] PrintingStrings/ParamTest.Failure/a`,
`+ull)m[----------] 2 tests from PrintingStrings/ParamTest`,
`+ull)m[ RUN      ] PrintingStrings/ParamTest.Success/a`,
`+ull)m[       OK ] PrintingStrings/ParamTest.Success/a`,
`+ull)m[ RUN      ] PrintingStrings/ParamTest.Failure/a`,
` gtest_output_test_.cc:#: Failure`,
` Expected equality of these values:`,
`   "b"`,
`@@ -627,7 +627,7 @@`,
``,
`     Which is: "a"`,
` Expected failure`,
` [  FAILED  ] PrintingStrings/ParamTest.Failure/a, where GetParam() = "a"`,
`-[----------] Global test environment tear-down`,
`+ull)m[----------] Global test environment tear-down`,
` BarEnvironment::TearDown() called.`,
` gtest_output_test_.cc:#: Failure`,
` Failed`,
`@@ -636,8 +636,8 @@`,
``,
` gtest_output_test_.cc:#: Failure`,
` Failed`,
` Expected fatal failure.`,
`-[==========] 66 tests from 29 test cases ran.`,
`-[  PASSED  ] 22 tests.`,
`+ull)m[==========] 66 tests from 29 test cases ran.`,
`+ull)m[  PASSED  ] 22 tests.`,
` [  FAILED  ] 44 tests, listed below:`,
` [  FAILED  ] NonfatalFailureTest.EscapesStringOperands`,
` [  FAILED  ] NonfatalFailureTest.DiffForLongStrings`,
        ];
    }
    // dfmt on
}
