/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.type;

import dextool.type : AbsolutePath;
import dextool.hash : Murmur3;

@safe:

alias Checksum = Murmur3;

/**
 * See: definitions.md for more information
 */
struct MutationPoint {
    Offset offset;
    Mutation[] mutations;
}

/// Offset range. It is a [) (closed->open).
struct Offset {
    uint begin;
    uint end;
}

Mutation.Kind[] rorMutations() @safe pure nothrow {
    with (Mutation.Kind) {
        return [rorLT, rorLE, rorGT, rorGE, rorEQ, rorNE,];
    }
}

Mutation.Kind[] lcrMutations() @safe pure nothrow {
    with (Mutation.Kind) {
        return [lcrAnd, lcrOr,];
    }
}

Mutation.Kind[] aorMutations() @safe pure nothrow {
    with (Mutation.Kind) {
        return [aorMul, aorDiv, aorRem, aorAdd, aorSub,];
    }
}

Mutation.Kind[] aorAssignMutations() @safe pure nothrow {
    with (Mutation.Kind) {
        return [aorAssignMul, aorAssignDiv, aorAssignRem, aorAssignAdd, aorAssignSub,];
    }
}

Mutation.Kind[] uoiLvalueMutations() @safe pure nothrow {
    with (Mutation.Kind) {
        return [uoiPostInc, uoiPostDec, uoiPreInc, uoiPreDec, uoiAddress, uoiIndirection,
            uoiPositive, uoiNegative, uoiComplement, uoiNegation, uoiSizeof_,];
    }
}

Mutation.Kind[] uoiRvalueMutations() @safe pure nothrow {
    with (Mutation.Kind) {
        return [uoiPreInc, uoiPreDec, uoiAddress, uoiIndirection, uoiPositive,
            uoiNegative, uoiComplement, uoiNegation, uoiSizeof_,];
    }
}

Mutation.Kind[] absMutations() @safe pure nothrow {
    with (Mutation.Kind) {
        return [absPos, absNeg, absZero,];
    }
}

/// A possible mutation and its status.
struct Mutation {
    /// States what kind of mutations that can be performed on this mutation point.
    enum Kind {
        /// the kind is not initialized thus can only ignore the point
        none,
        /// Relational operator replacement
        rorLT,
        rorLE,
        rorGT,
        rorGE,
        rorEQ,
        rorNE,
        /// Logical connector replacement
        lcrAnd,
        lcrOr,
        /// Arithmetic operator replacement
        aorMul,
        aorDiv,
        aorRem,
        aorAdd,
        aorSub,
        aorAssignMul,
        aorAssignDiv,
        aorAssignRem,
        aorAssignAdd,
        aorAssignSub,
        /// Unary operator insert on an lvalue
        uoiPostInc,
        uoiPostDec,
        // these work for rvalue
        uoiPreInc,
        uoiPreDec,
        uoiAddress,
        uoiIndirection,
        uoiPositive,
        uoiNegative,
        uoiComplement,
        uoiNegation,
        uoiSizeof_,
        /// Absolute value replacement
        absPos,
        absNeg,
        absZero,
    }

    enum Status {
        unknown,
        dead,
        alive
    }

    Kind kind;
    Status status;
}
