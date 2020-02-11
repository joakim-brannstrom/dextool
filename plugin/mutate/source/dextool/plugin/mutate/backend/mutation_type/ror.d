/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

#SPC-mutation_ror
*/
module dextool.plugin.mutate.backend.mutation_type.ror;

import std.array : empty;

import dextool.plugin.mutate.backend.type;

import dextool.plugin.mutate.backend.analyze.ast;

@safe:

/// Information used to intelligently generate ror mutants;
struct RorInfo {
    Kind operator;
    Type lhs;
    Symbol lhsSym;
    Type rhs;
    Symbol rhsSym;
}

/** Produce the mutations that can be applied on an operator.
 *
 * The resulting schema is intended to be:
 * normal + pointer - float - enum - bool
 *
 * The schema when used is:
 * ror = normal - float - enum - bool
 * rorp = pointer - float - enum - bool
 *
 * See SPC-mutation_ror for the subsumed table.
 */
auto rorMutations(RorInfo info) {
    import std.typecons : Tuple;
    import std.algorithm : among;

    alias Rval = Tuple!(Mutation.Kind[], "op", Mutation.Kind[], "expr");
    Rval rval;

    // initialize rval with the basic ROR schema
    switch (info.operator) with (Mutation.Kind) {
    case Kind.OpLess:
        rval = Rval([rorLE, rorpLE, rorNE, rorpNE], [rorFalse]);
        break;
    case Kind.OpGreater:
        rval = Rval([rorGE, rorpGE, rorNE, rorpNE], [rorFalse]);
        break;
    case Kind.OpLessEq:
        rval = Rval([rorLT, rorpLT, rorEQ, rorpEQ], [rorTrue]);
        break;
    case Kind.OpGreaterEq:
        rval = Rval([rorGT, rorpGT, rorEQ, rorpEQ], [rorTrue]);
        break;
    case Kind.OpEqual:
        rval = Rval([rorLE, rorpLE, rorGE, rorpGE], [rorFalse]);
        break;
    case Kind.OpNotEqual:
        rval = Rval([rorLT, rorpLT, rorGT, rorpGT], [rorTrue]);
        break;
    default:
    }

    // in case the operator isn't a ROR operator.
    if (rval.op.empty && rval.expr.empty)
        return rval;

    // #SPC-mutation_ror_enum
    void discreteSchema() {
        // information about the type and the concrete value of lhs is available
        if (info.lhs !is null && info.lhsSym !is null)
            with (Mutation.Kind) {
                const c = info.lhs.range.compare(info.lhsSym.value);

                if (c == Range.CompareResult.inside) {
                    // do nothing because lhs is inside thus all ROR mutants are possible
                } else if (info.operator.among(Kind.OpEqual, Kind.OpNotEqual)
                        && c.among(Range.CompareResult.onLowerBound,
                            Range.CompareResult.onUpperBound)) {
                    rval = Rval(null, [rorTrue, rorFalse]);
                }
            }

        if (info.rhs !is null && info.rhsSym !is null)
            with (Mutation.Kind) {
                const c = info.rhs.range.compare(info.rhsSym.value);

                if (c == Range.CompareResult.inside) {
                    // do nothing because lhs is inside thus all ROR mutants are possible
                } else if (info.operator.among(Kind.OpEqual, Kind.OpNotEqual)
                        && c.among(Range.CompareResult.onLowerBound,
                            Range.CompareResult.onUpperBound)) {
                    rval = Rval(null, [rorTrue, rorFalse]);
                }
            }
    }

    // #SPC-mutation_ror_float
    void continuesSchema() {
        switch (info.operator) with (Mutation.Kind) {
        case Kind.OpLess:
            rval.op = [rorGT, rorpGT];
            break;
        case Kind.OpGreater:
            rval.op = [rorLT, rorpLT];
            break;
        case Kind.OpLessEq:
            rval.op = [rorGT, rorpGT];
            break;
        case Kind.OpGreaterEq:
            rval.op = [rorLT, rorpLT];
            break;
        default:
        }
    }

    // #SPC-mutation_ror_bool
    void boolSchema() {
        switch (info.operator) with (Mutation.Kind) {
        case Kind.OpEqual:
            rval.op = [rorNE, rorpNE];
            break;
        case Kind.OpNotEqual:
            rval.op = [rorEQ, rorpEQ];
            break;
        default:
        }
    }

    // #SPC-mutation_ror_ptr
    void unorderedSchema() {
        switch (info.operator) with (Mutation.Kind) {
        case Kind.OpEqual:
            rval.op = [rorLE, rorGE, rorpNE];
            break;
        case Kind.OpNotEqual:
            rval.op = [rorLT, rorGT, rorpEQ];
            break;
        default:
        }
    }

    // Returns: true if either the type for lhs or rhs match `k`.
    bool isAny(TypeKind k) {
        if (info.lhs !is null && info.lhs.kind == k)
            return true;
        if (info.rhs !is null && info.rhs.kind == k)
            return true;
        return false;
    }

    if (isAny(TypeKind.unordered))
        unorderedSchema;
    else if (isAny(TypeKind.boolean))
        boolSchema;
    else if (isAny(TypeKind.continues))
        continuesSchema;
    else if (isAny(TypeKind.discrete))
        discreteSchema;

    return rval;
}

immutable Mutation.Kind[] rorMutationsAll;
immutable Mutation.Kind[] rorpMutationsAll;

shared static this() {
    with (Mutation.Kind) {
        rorMutationsAll = [
            rorLT, rorLE, rorGT, rorGE, rorEQ, rorNE, rorTrue, rorFalse
        ];
        rorpMutationsAll = [
            rorpLT, rorpLE, rorpGT, rorpGE, rorpEQ, rorpNE, rorTrue, rorFalse
        ];
    }
}
