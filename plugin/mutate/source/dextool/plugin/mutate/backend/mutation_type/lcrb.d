/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.mutation_type.lcrb;

import dextool.plugin.mutate.backend.type;
import dextool.clang_extensions : OpKind;

auto lcrbMutations(OpKind k) @safe pure nothrow {
    auto v = k in isLcrb;
    if (v is null)
        return null;

    if (*v == Mutation.Kind.lcrbAnd)
        return [Mutation.Kind.lcrbOr];
    else if (*v == Mutation.Kind.lcrbOr)
        return [Mutation.Kind.lcrbAnd];
    return null;
}

auto lcrbLhsMutations() @safe pure nothrow {
    return [Mutation.Kind.lcrbRhs];
}

auto lcrbRhsMutations() @safe pure nothrow {
    return [Mutation.Kind.lcrbLhs];
}

auto lcrbAssignMutations(OpKind k) @safe pure nothrow {
    auto v = k in isLcrbAssign;
    if (v is null)
        return null;

    if (*v == Mutation.Kind.lcrbAndAssign)
        return [Mutation.Kind.lcrbOrAssign];
    else if (*v == Mutation.Kind.lcrbOrAssign)
        return [Mutation.Kind.lcrbAndAssign];
    return null;
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
        lcrbMutationsAll = [lcrbAnd, lcrbOr, lcrbLhs, lcrbRhs];
        lcrbAssignMutationsAll = [lcrbOrAssign, lcrbAndAssign];
    }
}
