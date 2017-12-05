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
        aorMulAssign,
        aorDivAssign,
        aorRemAssign,
        aorAddAssign,
        aorSubAssign,
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
        /// statement deletion
        stmtDel
    }

    enum Status {
        /// the mutation isn't tested
        unknown,
        /// killed by the test suite
        killed,
        /// not killed by the test suite
        alive,
        /// the mutation resulted in invalid code that didn't compile
        killedByCompiler,
        /// the mutant resulted in the test suite/sut reaching the timeout threshold
        timeout,
    }

    Kind kind;
    Status status;
}
