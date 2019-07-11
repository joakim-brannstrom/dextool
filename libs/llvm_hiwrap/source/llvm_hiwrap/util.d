/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module llvm_hiwrap.util;

import llvm_hiwrap.types;

immutable(char*)* strToCArray(string[] arr) {
    import std.string : toStringz;

    if (arr is null)
        return null;

    immutable(char*)[] cArr;
    cArr.reserve(arr.length);

    foreach (str; arr)
        cArr ~= str.toStringz;

    return cArr.ptr;
}

/**
 * Beware, the data is duplicated and thus slightly inefficient.
 *
 * Params:
 *  msg = LLVM message to convert.
 */
string toD(ref LxMessage msg) {
    return msg.toChar.idup;
}

/// Create the needed InputRange operation when opIndex is implemented.
mixin template IndexedRangeX(T) {
    private size_t idx;

    T front() {
        assert(!empty, "Can't get front of an empty range");
        return this[idx];
    }

    void popFront() {
        assert(!empty, "Can't pop front of an empty range");
        idx++;
    }

    bool empty() {
        return idx == length;
    }
}
