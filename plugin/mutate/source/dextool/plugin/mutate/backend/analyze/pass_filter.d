/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Filter mutants based on simple textual pattern matching. These are the obvious
equivalent or undesired mutants.
*/
module dextool.plugin.mutate.backend.analyze.pass_filter;

import logger = std.experimental.logger;
import std.algorithm : among, map, filter, cache;
import std.array : appender, empty;
import std.typecons : Tuple;

import blob_model : Blob;

import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.type : Language, Offset, Mutation;
import dextool.plugin.mutate.backend.analyze.pass_mutant : MutantsResult;
import dextool.plugin.mutate.backend.generate_mutant : makeMutationText, MakeMutationTextResult;

@safe:

MutantsResult filterMutants(FilesysIO fio, MutantsResult mutants) {
    foreach (f; mutants.files.map!(a => a.path)) {
        logger.trace(f);
        auto file = fio.makeInput(f);
        foreach (r; mutants.getMutationPoints(f)
                .map!(a => analyzeForUndesiredMutant(file, a, mutants.lang))
                .cache
                .filter!(a => !a.kind.empty)) {
            foreach (k; r.kind) {
                mutants.drop(f, r.point, k);
            }
        }
    }

    return mutants;
}

private:

alias Mutants = Tuple!(Mutation.Kind[], "kind", MutantsResult.MutationPoint, "point");

/// Returns: mutants to drop from the mutation point.
Mutants analyzeForUndesiredMutant(Blob file, Mutants mutants, const Language lang) {
    auto app = appender!(Mutation.Kind[])();

    foreach (k; mutants.kind) {
        if (isEmpty(file, mutants.point.offset)) {
            logger.tracef("Dropping undesired mutant. Mutant is empty (%s %s %s)",
                    file.uri, mutants.point, k);
            app.put(k);
            continue;
        }

        auto mutant = makeMutationText(file, mutants.point.offset, k, lang);
        if (isTextuallyEqual(file, mutants.point.offset, mutant.rawMutation)) {
            logger.tracef("Dropping undesired mutant. Original and mutant is textually equivalent (%s %s %s)",
                    file.uri, mutants.point, k);
            app.put(k);
        } else if (lang.among(Language.assumeCpp, Language.cpp)
                && isUndesiredCppPattern(file, mutants.point.offset)) {
            logger.tracef("Dropping undesired mutant. The mutant is an undesired C++ mutant pattern (%s %s %s)",
                    file.uri, mutants.point, k);
            app.put(k);
        } else if (isOnlyWhitespace(file, mutants.point.offset, mutant.rawMutation)) {
            logger.tracef("Dropping undesired mutant. Both the original and the mutant is only whitespaces (%s %s %s)",
                    file.uri, mutants.point, k);
            app.put(k);
        }
    }

    return Mutants(app.data, mutants.point);
}

bool isEmpty(Blob file, Offset o) {
    // well an empty region can just be removed
    return o.isZero || o.end > file.content.length;
}

bool isTextuallyEqual(Blob file, Offset o, const(ubyte)[] mutant) {
    return file.content[o.begin .. o.end] == mutant;
}

// if both the original and mutation is only whitespace
bool isOnlyWhitespace(Blob file, Offset o, const(ubyte)[] mutant) {
    import std.algorithm : canFind;

    static immutable ubyte[6] whitespace = [
        cast(ubyte) ' ', cast(ubyte) '\t', cast(ubyte) '\v', cast(ubyte) '\r',
        cast(ubyte) '\n', cast(ubyte) '\f'
    ];

    bool rval = true;
    foreach (a; file.content[o.begin .. o.end]) {
        rval = rval && whitespace[].canFind(a);
    }

    foreach (a; mutant) {
        rval = rval && whitespace[].canFind(a);
    }

    return rval;
}

bool isUndesiredCppPattern(Blob file, Offset o) {
    static immutable ubyte[2] ctorParenthesis = [40, 41];
    static immutable ubyte[2] ctorCurly = [123, 125];

    // e.g. delete of the constructor {} is undesired. It is almost always an
    // equivalent mutant.
    if (o.end - o.begin == 2 && file.content[o.begin .. o.end].among(ctorParenthesis[],
            ctorCurly[])) {
        return true;
    }

    return false;
}
