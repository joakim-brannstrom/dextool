/**
Copyright: Copyright (c) 2018-2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Test utility for testing a sequence of data for expected content.
*/
module dextool_test.sequence;

import std.format : format;
import std.range : isRandomAccessRange, isInfinite;

import unit_threaded.exception : UnitTestException;

enum isInputSequence(T) = isRandomAccessRange!T && !isInfinite!T;

/// Check that the string is a substring of the one it is compared with.
struct SubStr {
    string key;

    bool opEquals(const string rhs) const {
        import std.string : indexOf;

        return rhs.indexOf(key) != -1;
    }
}

/** Make an object that test that actual pass the predicate function.
 *
 * Params:
 *  ElementType = the element type to convert `T1` to.
 *  T =
 *  PredFunc =
 *  expected =
 */
auto testOrder(ElementType, T, alias PredFun)(T expected,
        in string file = __FILE__, in size_t line = __LINE__) {
    import std.array : array;
    import std.algorithm : map;

    auto r = expected.map!(a => ElementType(a)).array;
    return TestSeq!(typeof(r), PredFun)(r, file, line);
}

/** Make an object that compares expected with actual where the test passes if
 * all expected elements are found in the tested range in any order.
 */
auto testAnyOrder(ElementType, T)(T expected, in string file = __FILE__, in size_t line = __LINE__) {
    return testOrder!(ElementType, T, predRandomOrder)(expected, file, line);
}

/// ditto
auto testAnyOrder(T)(T expected, in string file = __FILE__, in size_t line = __LINE__)
        if (isInputRange!T) {
    return TestSeq!(T, predRandomOrder)(expected, file, line);
}

/** Make an object that compares expected with actual where the test passes if
 * all expected elements are found in the tested range in consecutive order.
 */
auto testConsecutiveSparseOrder(ElementType, T)(T expected,
        in string file = __FILE__, in size_t line = __LINE__) {
    return testOrder!(ElementType, T, predConsecutiveSparseOrder)(expected, file, line);
}

/// ditto
auto testConsecutiveSparseOrder(T)(T expected, in string file = __FILE__, in size_t line = __LINE__)
        if (isInputRange!T) {
    return TestSeq!(T, predConsecutiveSparseOrder)(expected, file, line);
}

/** Make an object that compares expected with actual where the test passes if
 * all expected elements are found in the tested range in consecutive order.
 */
auto testBlockOrder(ElementType, T)(T expected, in string file = __FILE__, in size_t line = __LINE__) {
    return testOrder!(ElementType, T, predBlockOrder)(expected, file, line);
}

/// ditto
auto testBlockOrder(T)(T expected, in string file = __FILE__, in size_t line = __LINE__)
        if (isInputRange!T) {
    return TestSeq!(T, predBlockOrder)(expected, file, line);
}

/** Test that a sequence of sub-elements are found in the input range.
 */
struct TestSeq(SeqT, alias PredFun) {
    private {
        SeqT elems;
        string file;
        size_t line;
    }

    /**
     * Params:
     *  elems = sequence of elements to verify
     */
    this(SeqT elems, in string file = __FILE__, in size_t line = __LINE__) {
        this.elems = elems;
        this.file = file;
        this.line = line;
    }

    /// The whole sequence is found.
    void shouldBeIn(T)(T in_seq) if (isInputSequence!T) {
        auto res = this.isIn(in_seq);
        if (res.isElementsLeft) {
            throw new UnitTestException(res.msg, file, line);
        }
    }

    /// The whole sequence is NOT found.
    void shouldNotBeIn(T)(T in_seq) if (isInputSequence!T) {
        auto res = this.isIn(in_seq);
        if (res.isElementsLeft == 0) {
            throw new UnitTestException(res.msg, file, line);
        }
    }

    TestSeqResult isIn(T)(T in_seq) if (isInputSequence!T) {
        return PredFun(elems, in_seq);
    }
}

private struct TestSeqResult {
    // A human readable msg for what failed.
    string msg;
    // Elements left to test against the predicate.
    const size_t elementsLeft;
    // The element that failed the predicate.
    const size_t elementIndex;

    bool isElementsLeft() {
        return elementsLeft != 0;
    }
}

/// The expected elements must exist but may be in any order.
TestSeqResult predRandomOrder(T0, T1)(T0 expected, T1 actual)
        if (isInputSequence!T0 && isInputSequence!T1) {
    import std.algorithm : countUntil, remove;

    size_t last_element_idx;
    while (expected.length != 0) {
        if (countUntil(actual, expected[0]) != -1) {
            expected = remove(expected, 0);
            ++last_element_idx;
        } else {
            break;
        }
    }

    if (expected.length == 0) {
        return TestSeqResult();
    } else {
        return TestSeqResult(format("Expected (index:%s left:%s): %s\nActual:\n%(%s\n%)", last_element_idx,
                expected.length, expected[0], actual), expected.length, last_element_idx);
    }
}

/// The expected elements must be in order but may be distributed sparsely.
TestSeqResult predConsecutiveSparseOrder(T0, T1)(T0 expected, T1 actual)
        if (isInputSequence!T0 && isInputSequence!T1) {
    import std.range : take, enumerate;

    size_t last_expected;
    size_t last_actual;
    foreach (const s; actual.enumerate) {
        if (expected[last_expected] == s.value) {
            ++last_expected;
            last_actual = s.index;
        }

        if (last_expected == expected.length)
            return TestSeqResult();
    }

    auto left = expected.length - last_expected;
    return TestSeqResult(format("Expected (index:%s left:%s): %s\nActual (index:%s left:%s):\n%(%s\n%)",
            last_expected, left,
            expected[last_expected],
            last_actual, actual.length - last_actual, actual[last_actual .. $].take(3)),
            left, last_expected);
}

/// The actual data must contain the expected block of data.
TestSeqResult predBlockOrder(T0, T1)(T0 expected, T1 actual)
        if (isInputSequence!T0 && isInputSequence!T1) {
    import std.range : take, enumerate;

    bool last_actual;
    bool start_verifying;
    size_t next;
    foreach (const s; actual.enumerate) {
        if (!start_verifying && expected[next] == s.value)
            start_verifying = true;

        if (start_verifying && expected[next] == s.value) {
            ++next;
            last_actual = s.index;
        }

        if (next == expected.length)
            return TestSeqResult();
    }

    auto left = expected.length - next;
    return TestSeqResult(format("Expected (index:%s left:%s): %s\nActual (index:%s left:%s):\n%(%s\n%)", next, left,
            expected[next], last_actual, actual.length - last_actual,
            actual[last_actual .. $].take(3)), left, next);
}
