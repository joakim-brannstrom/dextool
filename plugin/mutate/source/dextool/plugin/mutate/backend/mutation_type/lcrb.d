/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.mutation_type.lcrb;

import std.algorithm : filter;

import dextool.plugin.mutate.backend.type;
import dextool.clang_extensions : OpKind;

auto lcrbMutations(Mutation.Kind is_a) @safe pure nothrow {
    return lcrbMutationsAll.filter!(a => a != is_a);
}

auto lcrbAssignMutations(Mutation.Kind is_a) @safe pure nothrow {
    return lcrbAssignMutationsAll.filter!(a => a != is_a);
}

immutable Mutation.Kind[OpKind] isLcrb;
immutable Mutation.Kind[OpKind] isLcrbAssign;

immutable Mutation.Kind[] lcrbMutationsAll;
immutable Mutation.Kind[] lcrbAssignMutationsAll;

shared static this() {
    // dfmt off
    with (OpKind) {
    isLcrb = [
        And : Mutation.Kind.lcrbAnd, // "&"
        Or : Mutation.Kind.lcrbOr, // "|"
        OO_Amp : Mutation.Kind.lcrbAnd, // "&"
        OO_Pipe : Mutation.Kind.lcrbOr, // "|"
    ];

    isLcrbAssign = [
        AndAssign : Mutation.Kind.lcrbAndAssign,
        OrAssign : Mutation.Kind.lcrbOrAssign,
        OO_AmpEqual : Mutation.Kind.lcrbAndAssign,
        OO_PipeEqual : Mutation.Kind.lcrbOrAssign,
    ];
    }
    // dfmt on

    with (Mutation.Kind) {
        lcrbMutationsAll = [lcrbAnd, lcrbOr];
        lcrbAssignMutationsAll = [lcrbOrAssign, lcrbAndAssign];
    }
}
