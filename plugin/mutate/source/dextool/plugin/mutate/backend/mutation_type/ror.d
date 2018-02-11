/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

#SPC-plugin_mutate_mutation_ror
*/
module dextool.plugin.mutate.backend.mutation_type.ror;

import dextool.plugin.mutate.backend.type;
import dextool.clang_extensions : OpKind;

/** Produce the mutations that can be applied on an operator.
 *
 * Params:
 *  op = the c/c++ operator in the AST
 *  tyi = type info about the expressions on the sides of the operator
 *
 * The resulting schema is intended to be:
 * normal + pointer - float - enum
 *
 * The schema when used is:
 * ror = normal - float - enum
 * rorp = pointer - float - enum
 *
 * See SPC-plugin_mutate_mutation_ror for the subsumed table.
 */
auto rorMutations(OpKind op, OpTypeInfo tyi) @safe pure nothrow {
    import std.typecons : Tuple, Nullable;
    import std.algorithm : among;

    alias Rval = Tuple!(Mutation.Kind[], "op", Mutation.Kind, "expr");

    Nullable!Rval rval;

    with (Mutation.Kind) {
        if (op.among(OpKind.LT, OpKind.OO_Less)) {
            rval = Rval([rorLE, rorpLE, rorNE, rorpNE], rorFalse);
        } else if (op.among(OpKind.GT, OpKind.OO_Greater)) {
            rval = Rval([rorGE, rorpGE, rorNE, rorpNE], rorFalse);
        } else if (op.among(OpKind.LE, OpKind.OO_LessEqual)) {
            rval = Rval([rorLT, rorpLT, rorEQ, rorpEQ], rorTrue);
        } else if (op.among(OpKind.GE, OpKind.OO_GreaterEqual)) {
            rval = Rval([rorGT, rorpGT, rorEQ, rorpEQ], rorTrue);
        } else if (op.among(OpKind.EQ, OpKind.OO_EqualEqual)) {
            rval = Rval([rorLE, rorpLE, rorGE, rorpGE], rorFalse);
        } else if (op.among(OpKind.NE, OpKind.OO_ExclaimEqual)) {
            rval = Rval([rorLT, rorpLT, rorGT, rorpGT], rorTrue);
        }
    }

    // #SPC-plugin_mutate_mutation_ror_float
    void floatingPointSchema() {
        with (Mutation.Kind) {
            if (op.among(OpKind.LT, OpKind.OO_Less)) {
                rval.op = [rorGT, rorpGT];
            } else if (op.among(OpKind.GT, OpKind.OO_Greater)) {
                rval.op = [rorLT, rorpLT];
            } else if (op.among(OpKind.LE, OpKind.OO_LessEqual)) {
                rval.op = [rorGT, rorpGT];
            } else if (op.among(OpKind.GE, OpKind.OO_GreaterEqual)) {
                rval.op = [rorLT, rorpLT];
            }
        }
    }

    // #SPC-plugin_mutate_mutation_ror_enum
    void enumSchema() {
        with (Mutation.Kind) {
            if (op.among(OpKind.EQ, OpKind.OO_EqualEqual)) {
                if (tyi == OpTypeInfo.enumLhsIsMin) {
                    rval.op = [rorGE, rorpGE];
                } else if (tyi == OpTypeInfo.enumRhsIsMax) {
                    rval.op = [rorLE, rorpLE];
                }
            } else if (op.among(OpKind.NE, OpKind.OO_ExclaimEqual)) {
                if (tyi == OpTypeInfo.enumLhsIsMin) {
                    rval.op = [rorGT, rorpGT];
                } else if (tyi == OpTypeInfo.enumRhsIsMax) {
                    rval.op = [rorLT, rorpLT];
                }
            }
        }
    }

    // #SPC-plugin_mutate_mutation_ror_ptr
    void pointerSchema() {
        with (Mutation.Kind) {
            if (op.among(OpKind.EQ, OpKind.OO_EqualEqual)) {
                rval.op = [rorLE, rorGE, rorpNE];
            } else if (op.among(OpKind.NE, OpKind.OO_ExclaimEqual)) {
                rval.op = [rorLT, rorGT, rorpEQ];
            }
        }
    }

    // #SPC-plugin_mutate_mutation_ror_bool
    void boolSchema() {
        with (Mutation.Kind) {
            if (op.among(OpKind.EQ, OpKind.OO_EqualEqual)) {
                rval.op = [rorNE, rorpNE];
            } else if (op.among(OpKind.NE, OpKind.OO_ExclaimEqual)) {
                rval.op = [rorEQ, rorpEQ];
            }
        }
    }

    if (tyi == OpTypeInfo.floatingPoint)
        floatingPointSchema();
    else if (tyi.among(OpTypeInfo.enumLhsIsMin, OpTypeInfo.enumRhsIsMax))
        enumSchema();
    else if (tyi == OpTypeInfo.pointer)
        pointerSchema();
    else if (tyi == OpTypeInfo.boolean)
        boolSchema();

    return rval;
}

immutable bool[OpKind] isRor;

immutable Mutation.Kind[] rorMutationsAll;
immutable Mutation.Kind[] rorpMutationsAll;

shared static this() {
    // dfmt off
    with (OpKind) {
    isRor =
        [
        LT: true, // "<"
        GT: true, // ">"
        LE: true, // "<="
        GE: true, // ">="
        EQ: true, // "=="
        NE: true, // "!="
        OO_Less: true, // "<"
        OO_Greater: true, // ">"
        OO_EqualEqual: true, // "=="
        OO_ExclaimEqual: true, // "!="
        OO_LessEqual: true, // "<="
        OO_GreaterEqual: true, // ">="
        ];
    }
    // dfmt on

    with (Mutation.Kind) {
        rorMutationsAll = [rorLT, rorLE, rorGT, rorGE, rorEQ, rorNE, rorTrue, rorFalse];
        rorpMutationsAll = [rorpLT, rorpLE, rorpGT, rorpGE, rorpEQ, rorpNE, rorTrue, rorFalse];
    }
}
