/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Utility useful for plugins.
*/
module plugin.utility;

version (unittest) {
    import unit_threaded : Name, shouldEqual;
} else {
    private struct Name {
        string name_;
    }
}

/** Make a static c'tor that creates an instance with all class members initialized.
 *
 * Params:
 *   T = type to construct an instance of
 *   postInit = call the function with the initialized instance.
 */
mixin template MakerInitializingClassMembers(T, alias postInit = function void(ref T) {
}) {
    static T make() {
        T inst;

        foreach (member; __traits(allMembers, T)) {
            alias MemberT = typeof(__traits(getMember, inst, member));
            static if (is(MemberT == class)) {
                __traits(getMember, inst, member) = new MemberT;
            }
        }

        postInit(inst);

        return inst;
    }
}

/** Convenient array with support for marking of elements for later removal.
 */
struct MarkArray(T) {
    alias Range = T[];
    private T[] arr;
    private size_t[] remove_;

    alias arr this;

    /// Store e in the cache.
    void put(T e) {
        arr ~= e;
    }

    /// Retrieve a slice of the stored data.
    T[] data() {
        return arr[];
    }

    /** Mark index `i` for removal.
     *
     * Later as in calling $(D doRemoval).
     */
    void markForRemoval(size_t i) @safe pure {
        remove_ ~= i;
    }

    /// Remove all items that has been marked.
    void doRemoval() {
        import std.algorithm : canFind, filter, cache, copy, map;
        import std.array : array;
        import std.range : enumerate;

        // naive implementation. Should use swapping instead.
        arr = arr[].enumerate.filter!(a => !canFind(remove_, a.index)).map!(a => a.value).array();
        remove_.length = 0;
    }
}

@Name("Should store item")
unittest {
    MarkArray!int arr;

    arr ~= 10;

    arr[].length.shouldEqual(1);
    arr[0].shouldEqual(10);
}

@Name("Should mark and remove items")
unittest {
    MarkArray!int arr;
    arr ~= [10, 20, 30];

    arr.markForRemoval(1);
    arr[].length.shouldEqual(3);

    arr.doRemoval;

    arr[].length.shouldEqual(2);
    arr[0].shouldEqual(10);
    arr[1].shouldEqual(30);
}
