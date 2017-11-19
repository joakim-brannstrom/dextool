/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.utility.sort;

import std.range.primitives : isInputRange;

/** Sort by using an index to remap the elements.
 *
 * TODO This is inefficient but gets the job done.
 *
 * Params:
 *   Pred = a func that takes arguments (Slice, indexA, indexB) and compares.
 */
auto indexSort(alias Pred, T)(T[] arr) @safe {
    import std.algorithm : makeIndex, map;

    auto index = new size_t[arr.length];
    makeIndex!((a, b) => Pred(a, b))(arr, index);

    return index.map!(a => arr[a]);
}

@("shall be a sorted array")
unittest {
    import std.array : array;
    import test.extra_should : shouldEqualPretty;

    string[] s = ["b", "c", "a", "d"];
    auto r = s.indexSort!((ref a, ref b) => a < b).array();

    r.shouldEqualPretty(["a", "b", "c", "d"]);
}
