/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file contains the interface used for reporting test cases that are found.
*/
module dextool.plugin.mutate.backend.test_mutant.interface_;

interface TestCaseReport {
    /// A test case that failed.
    void reportFailed(string name) @safe nothrow;

    /// A test case that failed.
    void reportFailed(string name, string file) @safe nothrow;

    /// A test case that is found
    void reportFound(string name) @safe nothrow;
}

/// A simple class to gather reported test cases.
class GatherTestCase : TestCaseReport {
    import std.algorithm : map;
    import std.array : array;
    import dextool.plugin.mutate.backend.type : TestCase;
    import dextool.set;

    /// Test cases reported as failed.
    long[string] failed;

    /// Found test cases.
    Set!string found;

    void merge(GatherTestCase o) @safe nothrow {
        foreach (kv; o.failed.byKeyValue) {
            if (auto v = kv.key in failed)
                (*v) += kv.value;
            else
                failed[kv.key] = kv.value;
        }

        foreach (k; o.found.byKey) {
            found.add(k);
        }
    }

    TestCase[] failedAsArray() @safe nothrow {
        return failed.byKey.map!(a => TestCase(a)).array;
    }

    TestCase[] foundAsArray() @safe nothrow {
        return found.byKey.map!(a => TestCase(a)).array;
    }

    override void reportFailed(string name) @safe nothrow {
        import std.format : format;

        this.reportFound(name);

        if (auto v = name in failed) {
            (*v)++;
        } else {
            failed[name] = 1;
        }
    }

    override void reportFailed(string name, string file) @safe nothrow {
        import std.exception : ifThrown;
        import std.format : format;

        this.reportFound(name);

        auto full_name = () {
            try
                return format("%s:%s", file, name);
            catch (Exception e)
                return name;
        }();
        if (auto v = full_name in failed) {
            (*v)++;
        } else {
            failed[full_name] = 1;
        }
    }

    /// A test case that is found
    override void reportFound(string name) @safe nothrow {
        found.add(name);
    }
}
