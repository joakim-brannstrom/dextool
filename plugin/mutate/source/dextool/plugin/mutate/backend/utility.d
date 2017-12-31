/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.utility;

import std.algorithm : filter;

import dextool.type : Path, AbsolutePath;

public import dextool.plugin.mutate.backend.type;
public import dextool.clang_extensions : OpKind;

Path trustedRelativePath(string p, AbsolutePath root) @trusted {
    import std.path : relativePath;

    return relativePath(p, root).Path;
}

/**
 * trusted: void[] is perfectly representable as ubyte[] accoding to the specification.
 */
Checksum checksum(const(ubyte)[] a) @safe {
    import dextool.hash : makeMurmur3;

    return makeMurmur3(a);
}

/// Package the values to a checksum.
Checksum ckecksum(T)(const(T[2]) a) @safe if (T.sizeof == 8) {
    return Checksum(cast(ulong) a[0], cast(ulong) a[1]);
}

/// Package the values to a checksum.
Checksum checksum(T)(const T a, const T b) @safe if (T.sizeof == 8) {
    return Checksum(cast(ulong) a, cast(ulong) b);
}

import dextool.plugin.mutate.type : MutationKind;

Mutation.Kind[] toInternal(MutationKind k) @safe pure nothrow {
    import std.traits : EnumMembers;

    final switch (k) with (MutationKind) {
    case any:
        return [EnumMembers!(Mutation.Kind)];
    case ror:
        return rorMutationsAll.dup;
    case lcr:
        return lcrMutationsAll.dup;
    case aor:
        return aorMutationsAll.dup ~ aorAssignMutationsAll;
    case uoi:
        return uoiLvalueMutations;
    case abs:
        return absMutations;
    case stmtDel:
        return stmtDelMutations;
    case cor:
        return corMutationsRaw.dup;
    case dcc:
        return dccMutationsRaw.dup;
    }
}

// See SPC-plugin_mutate_mutation_ror for the subsumed table.
auto rorMutations(OpKind op) @safe pure nothrow {
    import std.typecons : Tuple, Nullable;
    import std.algorithm : among;

    alias Rval = Tuple!(Mutation.Kind[], "op", Mutation.Kind, "expr");

    Nullable!Rval rval;

    with (Mutation.Kind) {
        if (op.among(OpKind.LT, OpKind.OO_Less)) {
            rval = Rval([rorLE, rorNE], rorFalse);
        } else if (op.among(OpKind.GT, OpKind.OO_Greater)) {
            rval = Rval([rorGE, rorNE], rorFalse);
        } else if (op.among(OpKind.LE, OpKind.OO_LessEqual)) {
            rval = Rval([rorLT, rorEQ], rorTrue);
        } else if (op.among(OpKind.GE, OpKind.OO_GreaterEqual)) {
            rval = Rval([rorGT, rorEQ], rorTrue);
        } else if (op.among(OpKind.EQ, OpKind.OO_EqualEqual)) {
            rval = Rval([rorLE, rorGE], rorFalse);
        } else if (op.among(OpKind.NE, OpKind.OO_ExclaimEqual)) {
            rval = Rval([rorLT, rorGT], rorTrue);
        }
    }

    return rval;
}

auto lcrMutations(Mutation.Kind is_a) @safe pure nothrow {
    return lcrMutationsAll.filter!(a => a != is_a);
}

auto aorMutations(Mutation.Kind is_a) @safe pure nothrow {
    return aorMutationsAll.filter!(a => a != is_a);
}

auto aorAssignMutations(Mutation.Kind is_a) @safe pure nothrow {
    return aorAssignMutationsAll.filter!(a => a != is_a);
}

/// What the operator should be replaced by.
auto corOpMutations(Mutation.Kind is_a) @safe pure nothrow {
    if (is_a == Mutation.Kind.corAnd) {
        return [Mutation.Kind.corEQ];
    } else if (is_a == Mutation.Kind.corOr) {
        return [Mutation.Kind.corNE];
    }

    return null;
}

/// What the expression should be replaced by.
auto corExprMutations(Mutation.Kind is_a) @safe pure nothrow {
    if (is_a == Mutation.Kind.corAnd) {
        return [Mutation.Kind.corFalse];
    } else if (is_a == Mutation.Kind.corOr) {
        return [Mutation.Kind.corTrue];
    }

    return null;
}

Mutation.Kind[] uoiLvalueMutations() @safe pure nothrow {
    return uoiLvalueMutationsRaw.dup;
}

Mutation.Kind[] uoiRvalueMutations() @safe pure nothrow {
    return uoiRvalueMutationsRaw.dup;
}

Mutation.Kind[] absMutations() @safe pure nothrow {
    return absMutationsRaw.dup;
}

Mutation.Kind[] stmtDelMutations() @safe pure nothrow {
    return stmtDelMutationsRaw.dup;
}

Mutation.Kind[] dccMutations() @safe pure nothrow {
    return dccMutationsRaw.dup;
}

immutable Mutation.Kind[OpKind] isRor;
immutable Mutation.Kind[OpKind] isLcr;
immutable Mutation.Kind[OpKind] isAor;
immutable Mutation.Kind[OpKind] isAorAssign;
immutable Mutation.Kind[OpKind] isCor;

immutable Mutation.Kind[] rorMutationsAll;
immutable Mutation.Kind[] lcrMutationsAll;
immutable Mutation.Kind[] aorMutationsAll;
immutable Mutation.Kind[] aorAssignMutationsAll;
immutable Mutation.Kind[] uoiLvalueMutationsRaw;
immutable Mutation.Kind[] uoiRvalueMutationsRaw;
immutable Mutation.Kind[] absMutationsRaw;
immutable Mutation.Kind[] stmtDelMutationsRaw;
immutable Mutation.Kind[] corMutationsRaw;
immutable Mutation.Kind[] dccMutationsRaw;

shared static this() {
    // dfmt off
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

    isLcr = cast(immutable)
        [
        LAnd: Mutation.Kind.lcrAnd, // "&&"
        LOr: Mutation.Kind.lcrOr, // "||"
        OO_AmpAmp: Mutation.Kind.lcrAnd, // "&&"
        OO_PipePipe: Mutation.Kind.lcrOr, // "||"
        ];

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

    isCor = cast(immutable)
        [
        LAnd: Mutation.Kind.corAnd, // "&&"
        LOr: Mutation.Kind.corOr, // "||"
        OO_AmpAmp: Mutation.Kind.corAnd, // "&&"
        OO_PipePipe: Mutation.Kind.corOr, // "||"
        ];
    }
    // dfmt on

    with (Mutation.Kind) {
        rorMutationsAll = [rorLT, rorLE, rorGT, rorGE, rorEQ, rorNE, rorTrue, rorFalse];
        lcrMutationsAll = [lcrAnd, lcrOr,];
        aorMutationsAll = [aorMul, aorDiv, aorRem, aorAdd, aorSub,];
        aorAssignMutationsAll = [aorMulAssign, aorDivAssign, aorRemAssign,
            aorAddAssign, aorSubAssign,];
        // inactivating unary that seem to be nonsense
        uoiLvalueMutationsRaw = [uoiPostInc, uoiPostDec, uoiPreInc, uoiPreDec, uoiNegation /*, uoiPositive, uoiNegative, uoiAddress,
            uoiIndirection, uoiComplement, uoiSizeof_,*/
        ];
        uoiRvalueMutationsRaw = [uoiPreInc, uoiPreDec, uoiNegative, uoiNegation, /*uoiAddress,
            uoiIndirection*, uoiPositive, uoiComplement, uoiSizeof_,*/
        ];
        absMutationsRaw = [absPos, absNeg, absZero,];
        stmtDelMutationsRaw = [stmtDel];
        corMutationsRaw = [corFalse, corLhs, corRhs, corEQ, corNE, corTrue];
        dccMutationsRaw = [dccTrue, dccFalse];
    }
}
