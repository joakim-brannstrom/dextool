/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.utility.dedup;

/// Return: sorted and deduplicated array of the range.
///TODO can it be implemented more efficient?
auto dedup(T)(T[] arr) {
    import std.algorithm : makeIndex, uniq, map;

    auto index = new size_t[arr.length];
    // sorting the indexes
    makeIndex(arr, index);

    // dfmt off
    return index
        // dedup the sorted index
        .uniq!((a,b) => arr[a] == arr[b])
        // reconstruct an array from the sorted indexes
        .map!(a => arr[a]);
    // dfmt on
}

@safe unittest {
    import std.array : array;

    string[] s = ["a", "b", "a"];
    auto r = s.dedup.array();

    assert(r == ["a", "b"]);
}
