/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.mutation_type.lcr;

import dextool.plugin.mutate.backend.type;
import dextool.clang_extensions : OpKind;

auto lcrMutations(OpKind k) @safe pure nothrow {
    import std.typecons : Tuple;

    alias Rval = Tuple!(Mutation.Kind[], "op", Mutation.Kind[], "expr");

    auto v = k in isLcr;
    if (v is null)
        return Rval();

    auto rval = Rval(null, [Mutation.Kind.lcrTrue, Mutation.Kind.lcrFalse]);

    if (*v == Mutation.Kind.lcrAnd) {
        rval.op = [Mutation.Kind.lcrOr];
    } else if (*v == Mutation.Kind.lcrOr) {
        rval.op = [Mutation.Kind.lcrAnd];
    }

    return rval;
}

auto lcrLhsMutations() @safe pure nothrow {
    return [Mutation.Kind.lcrRhs];
}

auto lcrRhsMutations() @safe pure nothrow {
    return [Mutation.Kind.lcrLhs];
}

immutable Mutation.Kind[OpKind] isLcr;

immutable Mutation.Kind[] lcrMutationsAll;

shared static this() {
    // dfmt off
    with (OpKind) {
    isLcr = cast(immutable)[
        LAnd : Mutation.Kind.lcrAnd, // "&&"
        LOr : Mutation.Kind.lcrOr, // "||"
        OO_AmpAmp : Mutation.Kind.lcrAnd, // "&&"
        OO_PipePipe : Mutation.Kind.lcrOr, // "||"
    ];
    }
    // dfmt on

    with (Mutation.Kind) {
        lcrMutationsAll = [lcrAnd, lcrOr, lcrLhs, lcrRhs, lcrTrue, lcrFalse];
    }
}
