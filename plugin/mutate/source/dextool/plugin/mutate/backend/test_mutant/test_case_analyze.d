/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.test_mutant.test_case_analyze;

import dextool.plugin.mutate.backend.type : TestCase;

/// A simple class to gather reported test cases.
struct GatherTestCase {
    import std.algorithm : map;
    import std.array : array;
    import my.set;

    /// Test cases reported as failed.
    long[TestCase] failed;

    /// The unstable test cases.
    Set!TestCase unstable;

    /// Found test cases.
    Set!TestCase found;

    void merge(GatherTestCase o) @safe nothrow {
        foreach (kv; o.failed.byKeyValue) {
            if (auto v = kv.key in failed)
                (*v) += kv.value;
            else
                failed[kv.key] = kv.value;
        }

        foreach (k; o.found.toRange) {
            found.add(k);
        }

        foreach (k; o.unstable.toRange) {
            unstable.add(k);
        }
    }

    TestCase[] failedAsArray() @safe nothrow {
        return failed.byKey.array;
    }

    TestCase[] foundAsArray() @safe nothrow {
        return found.toArray;
    }

    TestCase[] unstableAsArray() @safe nothrow {
        return unstable.toArray;
    }

    void reportFailed(TestCase tc) @safe nothrow {
        found.add(tc);

        if (auto v = tc in failed) {
            (*v)++;
        } else {
            failed[tc] = 1;
        }
    }

    /// A test case that is found
    void reportFound(TestCase tc) @safe nothrow {
        found.add(tc);
    }

    void reportUnstable(TestCase tc) @safe nothrow {
        found.add(tc);
        unstable.add(tc);
    }
}
