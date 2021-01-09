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

/// Information used to intelligently generate ror mutants;
struct AorInfo {
    Kind operator;
    Type lhs;
    Type rhs;
}

auto aorMutations(AorInfo info) @safe {
    // TODO: for AORs it is probably better to do one op and then lhs+rhs.
    alias Rval = Tuple!(Mutation.Kind[], "op", Mutation.Kind[], "lhs", Mutation.Kind[], "rhs");
    Rval rval;

    switch (info.operator) with (Mutation.Kind) {
    case Kind.OpAdd:
        rval = Rval([aorMul, aorDiv, aorRem, aorSub], null, null);
        break;
    case Kind.OpDiv:
        rval = Rval([aorMul, aorRem, aorAdd, aorSub], null, null);
        break;
    case Kind.OpMod:
        rval = Rval([aorMul, aorDiv, aorAdd, aorSub], null, null);
        break;
    case Kind.OpMul:
        rval = Rval([aorDiv, aorRem, aorAdd, aorSub], null, null);
        break;
    case Kind.OpSub:
        rval = Rval([aorMul, aorDiv, aorRem, aorAdd], null, null);
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

    // modulo do not work when either side is a floating point.
    // assume modulo (rem) is not possible if the type is unknown.
    if (info.lhs is null || info.rhs is null) {
        // do nothing
    } else if (info.lhs.kind == TypeKind.continues || info.rhs.kind == TypeKind.continues) {
        rval.op = rval.op.filter!(a => !a.among(Mutation.Kind.aorRem,
                Mutation.Kind.aorRemAssign)).array;
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
