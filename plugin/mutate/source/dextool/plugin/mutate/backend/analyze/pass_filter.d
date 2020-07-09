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
        auto mutant = makeMutationText(file, mutants.point.offset, k, lang);
        if (isTextuallyEqual(file, mutants.point.offset, mutant.rawMutation)) {
            logger.tracef("Dropping undesired mutant. Original and mutant is textually equivalent (%s %s %s)",
                    file.uri, mutants.point, k);
            app.put(k);
        } else if (lang.among(Language.assumeCpp, Language.cpp)
                && isUndesiredCppPattern(file, mutants.point.offset, mutant.rawMutation)) {
            logger.tracef("Dropping undesired mutant. The mutant is an undesired C++ mutant pattern (%s %s %s)",
                    file.uri, mutants.point, k);
            app.put(k);
        }
    }

    return Mutants(app.data, mutants.point);
}

bool isTextuallyEqual(Blob file, Offset o, const(ubyte)[] mutant) {
    return file.content[o.begin .. o.end] == mutant;
}

bool isUndesiredCppPattern(Blob file, Offset o, const(ubyte)[] mutant) {
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
