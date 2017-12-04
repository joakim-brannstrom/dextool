/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.utility;

public import dextool.plugin.mutate.backend.type;

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
        return rorMutationsRaw.dup;
    case lcr:
        return lcrMutationsRaw.dup;
    case aor:
        return aorMutationsRaw.dup ~ aorAssignMutationsRaw;
    case uoi:
        return uoiLvalueMutations;
    case abs:
        return absMutations;
    }
}

import std.algorithm : filter;

auto rorMutations(Mutation.Kind is_a) @safe pure nothrow {
    return rorMutationsRaw.filter!(a => a != is_a);
}

auto lcrMutations(Mutation.Kind is_a) @safe pure nothrow {
    return lcrMutationsRaw.filter!(a => a != is_a);
}

auto aorMutations(Mutation.Kind is_a) @safe pure nothrow {
    return aorMutationsRaw.filter!(a => a != is_a);
}

auto aorAssignMutations(Mutation.Kind is_a) @safe pure nothrow {
    return aorAssignMutationsRaw.filter!(a => a != is_a);
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

public import dextool.clang_extensions : OpKind;

immutable Mutation.Kind[OpKind] isRor;
immutable Mutation.Kind[OpKind] isLcr;
immutable Mutation.Kind[OpKind] isAor;
immutable Mutation.Kind[OpKind] isAorAssign;

immutable Mutation.Kind[] rorMutationsRaw;
immutable Mutation.Kind[] lcrMutationsRaw;
immutable Mutation.Kind[] aorMutationsRaw;
immutable Mutation.Kind[] aorAssignMutationsRaw;
immutable Mutation.Kind[] uoiLvalueMutationsRaw;
immutable Mutation.Kind[] uoiRvalueMutationsRaw;
immutable Mutation.Kind[] absMutationsRaw;

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
    }
    // dfmt on

    with (Mutation.Kind) {
        rorMutationsRaw = cast(immutable)[rorLT, rorLE, rorGT, rorGE, rorEQ, rorNE,];
        lcrMutationsRaw = cast(immutable)[lcrAnd, lcrOr,];
        aorMutationsRaw = cast(immutable)[aorMul, aorDiv, aorRem, aorAdd, aorSub,];
        aorAssignMutationsRaw = cast(immutable)[aorMulAssign, aorDivAssign,
            aorRemAssign, aorAddAssign, aorSubAssign,];
        uoiLvalueMutationsRaw = cast(immutable)[uoiPostInc, uoiPostDec, uoiPreInc, uoiPreDec, uoiAddress,
            uoiIndirection, uoiPositive, uoiNegative, uoiComplement, uoiNegation, uoiSizeof_,];
        uoiRvalueMutationsRaw = cast(immutable)[uoiPreInc, uoiPreDec, uoiAddress,
            uoiIndirection, uoiPositive, uoiNegative, uoiComplement, uoiNegation, uoiSizeof_,];
        absMutationsRaw = cast(immutable)[absPos, absNeg, absZero,];
    }
}
