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
import std.range : only;
import std.typecons : Tuple;

import dextool.plugin.mutate.backend.type;
import dextool.clang_extensions : OpKind;

import dextool.plugin.mutate.backend.analyze.ast;

/// Information used to intelligently generate ror mutants;
struct AorInfo {
    Kind operator;
    Type lhs;
    Type rhs;
    bool isOverloaded;
}

auto aorMutations(AorInfo info) @safe {
    // TODO: for AORs it is probably better to do one op and then lhs+rhs.
    alias Rval = Tuple!(Mutation.Kind[], "op", Mutation.Kind[], "lhs",
            Mutation.Kind[], "rhs", Mutation.Kind, "simple");

    Rval rval;
    switch (info.operator) with (Mutation.Kind) {
    case Kind.OpAdd:
        rval = Rval([aorMul, aorDiv, aorRem, aorSub], null, null, aorsSub);
        break;
    case Kind.OpDiv:
        rval = Rval([aorMul, aorRem, aorAdd, aorSub], null, null, aorsMul);
        break;
    case Kind.OpMod:
        rval = Rval([aorMul, aorDiv, aorAdd, aorSub], null, null, aorsDiv);
        break;
    case Kind.OpMul:
        rval = Rval([aorDiv, aorRem, aorAdd, aorSub], null, null, aorsDiv);
        break;
    case Kind.OpSub:
        rval = Rval([aorMul, aorDiv, aorRem, aorAdd], null, null, aorsAdd);
        break;
    case Kind.OpAssignAdd:
        rval = Rval([aorDivAssign, aorRemAssign,
                aorMulAssign, aorSubAssign], null, null, aorsSubAssign);
        break;
    case Kind.OpAssignDiv:
        rval = Rval([aorAddAssign, aorRemAssign,
                aorMulAssign, aorSubAssign], null, null, aorsMulAssign);
        break;
    case Kind.OpAssignMod:
        rval = Rval([aorAddAssign, aorDivAssign,
                aorMulAssign, aorSubAssign], null, null, aorsDivAssign);
        break;
    case Kind.OpAssignMul:
        rval = Rval([aorAddAssign, aorDivAssign,
                aorRemAssign, aorSubAssign], null, null, aorsDivAssign);
        break;
    case Kind.OpAssignSub:
        rval = Rval([aorAddAssign, aorDivAssign,
                aorRemAssign, aorMulAssign], null, null, aorsAddAssign);
        break;
    default:
    }

    if (info.lhs is null || info.rhs is null) {
        // block aor when the type is unknown. It is better to only mutate when
        // it is certain to be a "good" mutant.
        rval = typeof(rval).init;
    } else if (info.lhs.kind.among(TypeKind.unordered, TypeKind.bottom)
            || info.rhs.kind.among(TypeKind.unordered, TypeKind.bottom)) {
        if (info.isOverloaded) {
            // TODO: unfortunately this also blocks operator overloading which is [unordered, unordered].
            // block aor when the type is a pointer
        } else {
            // block AOR for pointers.
            rval = typeof(rval).init;
        }
    } else if (info.lhs.kind == TypeKind.continues || info.rhs.kind == TypeKind.continues) {
        // modulo do not work when either side is a floating point.
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
