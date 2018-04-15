/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

#SPC-plugin_mutate_track_ctest

# Design
The parser is a strict Moore FSM.
The FSM is small enough that a switch implementation is good enough, clear and explicit.

The parser has a strict separation of the *next state* and *action*.
This is to make it easier to unittest the FSM is so is needed.
It also makes it easier to understand what the state transitions are dependent on and when an action is performed.

The calculation of the next state is a strongly pure function to enforce that it is only dependent on the input. See: `nextState`.
*/
module dextool.plugin.mutate.backend.test_mutant.ctest_post_analyze;

import std.exception : collectException;
import std.range : isInputRange, isOutputRange;
import logger = std.experimental.logger;

import dextool.type : AbsolutePath;
import dextool.plugin.mutate.backend.type : TestCase;

/** Parse input for ctest test cases.
Params:
    r = range that is chunked by line
    sink = an output that accepts values of type TestCase via `put`.
  */
struct CtestParser {
    import std.regex : regex, ctRegex, matchFirst;

    private {
        // example: The following tests FAILED:
        enum re_start_failing_tc_list = ctRegex!(`^\s*The following tests FAILED`);
        // example: 40 - gtest-typed-test_test (OTHER_FAULT)
        enum re_fail_msg = ctRegex!(`^\s*\d*\s*-\s*(?P<tc>.*?)\s*\(.*\)`);
        // example: Errors while running CTest
        enum re_end_failing_tc_list = ctRegex!(`^\s*Errors while running CTest`);

        FsmData data;
    }

    void process(T, T1)(T line, ref T1 sink) {
        import std.range : put;
        import std.string : strip;

        auto fail_msg_match = matchFirst(line, re_fail_msg);
        data.hasStartOfList = !matchFirst(line, re_start_failing_tc_list).empty;
        data.hasFailedMessage = !fail_msg_match.empty;
        data.hasEndOfList = !matchFirst(line, re_end_failing_tc_list).empty;

        {
            auto rval = nextState(data);
            data.st = rval[0];
            data.act = rval[1];
        }

        final switch (data.act) with (Action) {
        case none:
            break;
        case putTestCase:
            put(sink, TestCase(fail_msg_match["tc"].strip.idup));
            break;
        }
    }
}

private:

enum State {
    findStartOfList,
    extractTestCase,
}

enum Action {
    none,
    putTestCase,
}

struct FsmData {
    State st;
    Action act;

    bool hasStartOfList;
    bool hasFailedMessage;
    bool hasEndOfList;
}

auto nextState(immutable FsmData d) @safe pure nothrow @nogc {
    import std.typecons : tuple;

    State next = d.st;
    Action act = d.act;

    final switch (d.st) with (State) {
    case findStartOfList:
        act = Action.none;
        if (d.hasStartOfList)
            next = extractTestCase;
        break;
    case extractTestCase:
        act = Action.none;
        if (d.hasFailedMessage)
            act = Action.putTestCase;
        else if (d.hasEndOfList)
            next = findStartOfList;
        break;
    }

    return tuple(next, act);
}
