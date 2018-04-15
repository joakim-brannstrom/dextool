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
        enum re_run_block = ctRegex!(`^\[\s*RUN\s*\]`);
        enum re_fail_msg = ctRegex!(`^(?P<file>.*?):.*Failure`);
        enum re_failed_block = ctRegex!(`^\[\s*FAILED\s*\]\s*(?P<tc>.*)`);

        AbsolutePath reldir;
        FsmData data;
        string fail_msg_file;
    }

    this(AbsolutePath reldir) {
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
    // dfmt on
}
}
