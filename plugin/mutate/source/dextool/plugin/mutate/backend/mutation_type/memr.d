/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.mutation_type.memr;

import std.algorithm : map, canFind;

import dextool.plugin.mutate.backend.type;

import dextool.plugin.mutate.backend.analyze.ast;

struct MemrInfo {
    Kind node;
    SymbolId tid;
}

Mutation.Kind[] memrMutations(MemrInfo info) @safe pure nothrow {
    Mutation.Kind[] rval;

    switch (info.node) with (Mutation.Kind) {
    case Kind.Call:
        if (mallocId.canFind(info.tid))
            rval = [memrNull];
        break;
    default:
    }

    return rval;
}

immutable Mutation.Kind[] memrMutationsAll;
private immutable SymbolId[] mallocId;

shared static this() {
    import std.array : array;
    import std.range : only;

    with (Mutation.Kind) {
        memrMutationsAll = [memrNull];
    }

    // matches the C version of malloc. the function name is the identifier.
    mallocId = only("malloc", "xmalloc", "kmalloc").map!(
            a => makeId!SymbolId(cast(const(ubyte)[]) a)).array;
}
