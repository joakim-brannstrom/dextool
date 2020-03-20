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

import dextool.plugin.mutate.backend.analyze.ast;

auto aorMutations(Kind operator) @safe pure nothrow {
    alias Rval = Tuple!(Mutation.Kind[], "op", Mutation.Kind[], "lhs", Mutation.Kind[], "rhs");
    Rval rval;

    switch (operator) with (Mutation.Kind) {
    case Kind.OpAdd:
        rval = Rval([aorMul, aorDiv, aorRem, aorSub],
                [Mutation.Kind.aorLhs], [Mutation.Kind.aorRhs]);
        break;
    case Kind.OpDiv:
        rval = Rval([aorMul, aorRem, aorAdd, aorSub],
                [Mutation.Kind.aorLhs], [Mutation.Kind.aorRhs]);
        break;
    case Kind.OpMod:
        rval = Rval([aorMul, aorDiv, aorAdd, aorSub],
                [Mutation.Kind.aorLhs], [Mutation.Kind.aorRhs]);
        break;
    case Kind.OpMul:
        rval = Rval([aorDiv, aorRem, aorAdd, aorSub],
                [Mutation.Kind.aorLhs], [Mutation.Kind.aorRhs]);
        break;
    case Kind.OpSub:
        rval = Rval([aorMul, aorDiv, aorRem, aorAdd],
                [Mutation.Kind.aorLhs], [Mutation.Kind.aorRhs]);
        break;
    case Kind.OpAssignAdd:
        rval = Rval([aorDivAssign, aorRemAssign,
                aorMulAssign, aorSubAssign], null, null);
        break;
    case Kind.OpAssignDiv:
        rval = Rval([aorAddAssign, aorRemAssign,
                aorMulAssign, aorSubAssign], null, null);
        break;
    case Kind.OpAssignMod:
        rval = Rval([aorAddAssign, aorDivAssign,
                aorMulAssign, aorSubAssign], null, null);
        break;
    case Kind.OpAssignMul:
        rval = Rval([aorAddAssign, aorDivAssign,
                aorRemAssign, aorSubAssign], null, null);
        break;
    case Kind.OpAssignSub:
        rval = Rval([aorAddAssign, aorDivAssign,
                aorRemAssign, aorMulAssign], null, null);
        break;
    default:
    }

    return rval;
}

immutable Mutation.Kind[] aorMutationsAll;
immutable Mutation.Kind[] aorAssignMutationsAll;

shared static this() {
    with (Mutation.Kind) {
        aorMutationsAll = [
            aorMul, aorDiv, aorRem, aorAdd, aorSub, aorLhs, aorRhs
        ];
        aorAssignMutationsAll = [
            aorMulAssign, aorDivAssign, aorRemAssign, aorAddAssign, aorSubAssign
        ];
    }
}
