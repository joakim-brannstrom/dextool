/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.mutation_type.aor;

import std.algorithm : filter, among;
import std.array : array;
import std.typecons : Tuple;

import dextool.plugin.mutate.backend.type;
import dextool.clang_extensions : OpKind;

Mutation.Kind[] aorMutations(OpKind k) @safe pure nothrow {
    auto v = k in isAor;
    if (v is null)
        return null;

    return aorMutationsAll.dup.filter!(a => !a.among(*v,
            Mutation.Kind.aorRhs, Mutation.Kind.aorLhs)).array;
}

Mutation.Kind[] aorAssignMutations(OpKind k) @safe pure nothrow {
    auto v = k in isAorAssign;
    if (v is null)
        return null;

    return aorAssignMutationsAll.dup.filter!(a => !a.among(*v,
            Mutation.Kind.aorRhs, Mutation.Kind.aorLhs)).array;
}

auto aorLhsMutations(OpKind k) @safe pure nothrow {
    return k in isAor ? [Mutation.Kind.aorLhs] : null;
}

auto aorRhsMutations(OpKind k) @safe pure nothrow {
    return k in isAor ? [Mutation.Kind.aorRhs] : null;
}

immutable Mutation.Kind[OpKind] isAor;
immutable Mutation.Kind[OpKind] isAorAssign;

immutable Mutation.Kind[] aorMutationsAll;
immutable Mutation.Kind[] aorAssignMutationsAll;
shared static this() {
    // dfmt off
    with (OpKind) {
    isAor = cast(immutable)
        [
        Mul: Mutation.Kind.aorMul, // "*"
        Div: Mutation.Kind.aorDiv, // "/"
        Rem: Mutation.Kind.aorRem, // "%"
        Add: Mutation.Kind.aorAdd, // "+"
        Sub: Mutation.Kind.aorSub, // "-"
        OO_Plus: Mutation.Kind.aorAdd, // "+"
        OO_Minus: Mutation.Kind.aorSub, // "-"
        OO_Star: Mutation.Kind.aorMul, // "*"
        OO_Slash: Mutation.Kind.aorDiv, // "/"
        OO_Percent: Mutation.Kind.aorRem, // "%"
        ];

    isAorAssign = cast(immutable)
        [
        MulAssign: Mutation.Kind.aorMulAssign, // "*="
        DivAssign: Mutation.Kind.aorDivAssign, // "/="
        RemAssign: Mutation.Kind.aorRemAssign, // "%="
        AddAssign: Mutation.Kind.aorAddAssign, // "+="
        SubAssign: Mutation.Kind.aorSubAssign, // "-="
        OO_PlusEqual: Mutation.Kind.aorAddAssign, // "+="
        OO_MinusEqual: Mutation.Kind.aorSubAssign, // "-="
        OO_StarEqual: Mutation.Kind.aorMulAssign, // "*="
        OO_SlashEqual: Mutation.Kind.aorDivAssign, // "/="
        OO_PercentEqual: Mutation.Kind.aorRemAssign, // "%="
        ];
    }
    // dfmt on

    with (Mutation.Kind) {
        aorMutationsAll = [aorMul, aorDiv, aorRem, aorAdd, aorSub, aorLhs, aorRhs];
        aorAssignMutationsAll = [aorMulAssign, aorDivAssign, aorRemAssign,
            aorAddAssign, aorSubAssign];
    }
}
