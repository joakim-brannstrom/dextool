/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.mutation_type.ror;

import dextool.plugin.mutate.backend.type;
import dextool.clang_extensions : OpKind;

// See SPC-plugin_mutate_mutation_ror for the subsumed table.
auto rorMutations(OpKind op, OpTypeInfo tyi) @safe pure nothrow {
    import std.typecons : Tuple, Nullable;
    import std.algorithm : among;

    alias Rval = Tuple!(Mutation.Kind[], "op", Mutation.Kind, "expr");

    Nullable!Rval rval;

    with (Mutation.Kind) {
        if (op.among(OpKind.LT, OpKind.OO_Less)) {
            rval = Rval([rorLE, rorNE], rorFalse);
            if (tyi == OpTypeInfo.floatingPoint) {
                rval.op = [rorGT];
            }
        } else if (op.among(OpKind.GT, OpKind.OO_Greater)) {
            rval = Rval([rorGE, rorNE], rorFalse);
            if (tyi == OpTypeInfo.floatingPoint) {
                rval.op = [rorLT];
            }
        } else if (op.among(OpKind.LE, OpKind.OO_LessEqual)) {
            rval = Rval([rorLT, rorEQ], rorTrue);
            if (tyi == OpTypeInfo.floatingPoint) {
                rval.op = [rorGT];
            }
        } else if (op.among(OpKind.GE, OpKind.OO_GreaterEqual)) {
            rval = Rval([rorGT, rorEQ], rorTrue);
            if (tyi == OpTypeInfo.floatingPoint) {
                rval.op = [rorLT];
            }
        } else if (op.among(OpKind.EQ, OpKind.OO_EqualEqual)) {
            rval = Rval([rorLE, rorGE], rorFalse);
            if (tyi == OpTypeInfo.enumLhsIsMin) {
                rval.op = [rorGE];
            } else if (tyi == OpTypeInfo.enumRhsIsMax) {
                rval.op = [rorLE];
            }
        } else if (op.among(OpKind.NE, OpKind.OO_ExclaimEqual)) {
            rval = Rval([rorLT, rorGT], rorTrue);
            if (tyi == OpTypeInfo.enumLhsIsMin) {
                rval.op = [rorGT];
            } else if (tyi == OpTypeInfo.enumRhsIsMax) {
                rval.op = [rorLT];
            }
        }
    }

    return rval;
}

immutable Mutation.Kind[OpKind] isRor;

immutable Mutation.Kind[] rorMutationsAll;

shared static this() {
    with (OpKind) {
    isRor = cast(immutable)
        [
        LT: Mutation.Kind.rorLT, // "<"
        GT: Mutation.Kind.rorGT, // ">"
        LE: Mutation.Kind.rorLE, // "<="
        GE: Mutation.Kind.rorGE, // ">="
        EQ: Mutation.Kind.rorEQ, // "=="
        NE: Mutation.Kind.rorNE, // "!="
        OO_Less: Mutation.Kind.rorLT, // "<"
        OO_Greater: Mutation.Kind.rorGT, // ">"
        OO_EqualEqual: Mutation.Kind.rorEQ, // "=="
        OO_ExclaimEqual: Mutation.Kind.rorNE, // "!="
        OO_LessEqual: Mutation.Kind.rorLE, // "<="
        OO_GreaterEqual: Mutation.Kind.rorGE, // ">="
        ];
    }

    with (Mutation.Kind) {
        rorMutationsAll = [rorLT, rorLE, rorGT, rorGE, rorEQ, rorNE, rorTrue, rorFalse];
    }
}
