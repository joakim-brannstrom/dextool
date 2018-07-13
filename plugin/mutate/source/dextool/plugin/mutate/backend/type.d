/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.type;

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

/// Offset range. It is a `[)` (closed->open).
struct Offset {
    uint begin;
    uint end;
}

/// Location in the source code.
struct SourceLoc {
    uint line;
    uint column;
}

/// A possible mutation and its status.
struct Mutation {
    /// States what kind of mutations that can be performed on this mutation point.
    // ONLY ADD NEW ITEMS TO THE END
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
        stmtDel,
        /// Conditional Operator Replacement (reduced set)
        corAnd,
        corOr,
        corFalse,
        corLhs,
        corRhs,
        corEQ,
        corNE,
        corTrue,
        /// Relational operator replacement
        rorTrue,
        rorFalse,
        /// Decision/Condition Coverage
        dccTrue,
        dccFalse,
        dccBomb,
        /// Decision/Condition Requirement
        dcrCaseDel,
        /// Relational operator replacement for pointers
        rorpLT,
        rorpLE,
        rorpGT,
        rorpGE,
        rorpEQ,
        rorpNE,
        /// Logical Operator Replacement Bit-wise (lcrb)
        lcrbAnd,
        lcrbOr,
        lcrbAndAssign,
        lcrbOrAssign,
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

    enum Equivalence {
        /// not yet tested
        unknown,
        /// testcase found that kill the mutant
        not_equivalent,
        /// alive after full path exploration
        equivalent,
        /// timed out
        timeout,
    }


    Kind kind;
    Status status;
    Equivalence eq;
}

/// Deducted type information for expressions on the sides of a relational operator
enum OpTypeInfo {
    none,
    /// Both sides are floating points
    floatingPoint,
    /// Either side is a pointer
    pointer,
    /// Both sides are bools
    boolean,
    /// lhs and rhs sides are the same enum decl
    enumLhsRhsIsSame,
    /// lhs is the minimal representation in the enum type
    enumLhsIsMin,
    /// lhs is the maximum representation in the enum type
    enumLhsIsMax,
    /// rhs is the minimum representation in the enum type
    enumRhsIsMin,
    /// rhs is the maximum representation in the enum type
    enumRhsIsMax,
}

/// A test case that failed and thus killed a mutant.
struct TestCase {
    string value;
    alias value this;
}

/// The language a file or mutant is.
enum Language {
    /// the default is assumed to be c++
    assumeCpp,
    ///
    cpp,
    ///
    c
}
