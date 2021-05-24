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
    Set!TestCase failed;

    /// The unstable test cases.
    Set!TestCase unstable;

    /// Found test cases.
    Set!TestCase found;

    Set!TestCase testCmd;

    void merge(GatherTestCase o) @safe nothrow {
        failed.add(o.failed);
        found.add(o.found);
        unstable.add(o.unstable);
    }

    void reportFailed(TestCase tc) @safe nothrow {
        found.add(tc);
        failed.add(tc);
    }

    /// A test case that is found
    void reportFound(TestCase tc) @safe nothrow {
        found.add(tc);
    }

    void reportUnstable(TestCase tc) @safe nothrow {
        found.add(tc);
        unstable.add(tc);
    }

    void reportTestCmd(TestCase tc) @safe nothrow {
        testCmd.add(tc);
        found.add(tc);
    }
}
