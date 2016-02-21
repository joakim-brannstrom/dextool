// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module test.helpers;

import std.ascii : newline;
import std.traits : isSomeString;

import unit_threaded : Name;

version (unittest) {
    import unit_threaded : shouldEqual;
}

/**
 * Verify in lockstep that the two values are the same.
 * Useful when the values can be treated as ranges.
 * The lockstep comparison then results in a more comprehensible failure
 * message.
 *
 * Throws: UnitTestException on failure
 * Params:
 *  value = actual value.
 *  expected = expected value.
 *  file = file check is in.
 *  line = line check is on.
 */
void shouldEqualPretty(V, E)(lazy V value, lazy E expected, string file = __FILE__,
        size_t line = __LINE__) if (!isAllSomeString!(V, E)) {
    import std.algorithm : count;
    import std.range : lockstep;
    import unit_threaded : shouldEqual, UnitTestException;
    import std.conv : text;

    size_t idx;

    try {
        foreach (index, val, exp; lockstep(value, expected)) {
            idx = index;
            shouldEqual(val, exp, file, line);
        }
    }
    catch (UnitTestException ex) {
        string[] lines = ["Chunk:" ~ idx.text, ex.toString()];
        throw new UnitTestException(lines, file, line);
    }

    shouldEqual(count(value), count(expected), file, line);
}

@Name("shouldEqualPretty should throw the first value that is different")
unittest {
    import unit_threaded : UnitTestException;

    string msg;
    try {
        auto value = [0, 2, 1];
        auto expected = [0, 1, 2];
        shouldEqualPretty!(typeof(value), typeof(expected))(value, expected, "file.d", 123);

        assert(false, "Didn't throw exception");
    }
    catch (UnitTestException ex) {
        msg = ex.toString;
    }

    msg = "foo";
    shouldEqualPretty(msg, "foo");
    shouldEqual(msg, "foo");
}

/**
 * Split with sep and verify in lockstep that the two values are the same.
 *
 * Throws: UnitTestException on failure.
 * Params:
 *  value = actual value.
 *  expected = expected value.
 *  sep = separator to split value and expected on.
 *  file = file check is in.
 *  line = line check is on.
 */
void shouldEqualPretty(V, E, Separator)(lazy V value, lazy E expected,
        lazy Separator sep, string file = __FILE__, size_t line = __LINE__)
        if (!isAllSomeString!(V, E)) {
    import std.algorithm : splitter;

    auto rValue = value.splitter(sep);
    auto rExpected = expected.splitter(sep);

    shouldEqualPretty!(typeof(rValue), typeof(rExpected))(rValue, rExpected, file, line);
}

/**
 * Verify that two strings are the same.
 * Performs tests per line to better isolate when a difference is found.
 *
 * Throws: UnitTestException on failure
 * Params:
 *  value = actual value.
 *  expected = expected value.
 *  file = file check is in.
 *  line = line check is on.
 */
void shouldEqualPretty(V, E)(lazy V value, lazy E expected, lazy string sep = newline,
        string file = __FILE__, size_t line = __LINE__) if (isAllSomeString!(V, E)) {
    import std.algorithm : splitter;

    auto rValue = value.splitter(sep);
    auto rExpected = expected.splitter(sep);

    shouldEqualPretty!(typeof(rValue), typeof(rExpected))(rValue, rExpected, file, line);
}

private:
enum isAllSomeString(T0, T1) = isSomeString!T0 && isSomeString!T1;
