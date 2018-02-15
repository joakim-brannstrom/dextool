/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.utility;

import std.exception : collectException;
import logger = std.experimental.logger;

import dextool.type;

import dextool.plugin.mutate.backend.type : Mutation, Offset;
import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.interface_ : FilesysIO, SafeInput;

@safe:

// 5 because it covers all the operators and true/false
immutable windowSize = 5;

immutable originalIsCorrupt = "deXtool: unable to open the file or it has changed since mutation where performed";

immutable invalidFile = "Dextool: Invalid UTF-8 content";

/// Create a range from `a` that has at most maxlen+3 letters in it.
auto window(T)(T a, size_t maxlen) {
    import std.algorithm : filter, among, joiner;
    import std.range : take, only, chain;

    // dfmt off
    return chain(a.take(maxlen).filter!(a => !a.among('\n')),
                 only(a.length > maxlen ? "..." : null).joiner);
    // dfmt on
}

struct MakeMutationTextResult {
    string original = originalIsCorrupt;
    string mutation;

    nothrow @safe size_t toHash() {
        import std.digest.murmurhash;

        MurmurHash3!32 hash;
        hash.put(cast(const(ubyte)[]) original);
        hash.put(cast(const(ubyte)[]) mutation);
        auto h = hash.finish;
        return ((h[0] << 24) | (h[1] << 16) | (h[2] << 8) | h[3]);
    }

    bool opEquals(const this o) const nothrow @safe {
        return original == o.original && mutation == o.mutation;
    }
}

auto makeMutationText(SafeInput file_, const Offset offs, Mutation.Kind kind) nothrow {
    import dextool.plugin.mutate.backend.generate_mutant : makeMutation;

    MakeMutationTextResult rval;

    try {
        if (offs.end < file_.read.length) {
            rval.original = file_.read[offs.begin .. offs.end].toInternal;
        }

        auto mut = makeMutation(kind);
        rval.mutation = mut.mutate(rval.original);
    }
    catch (Exception e) {
        logger.warning(e.msg).collectException;
    }

    return rval;
}

string toInternal(ubyte[] data) @safe nothrow {
    import std.utf : validate;

    try {
        auto result = () @trusted{ return cast(string) data; }();
        validate(result);
        return result;
    }
    catch (Exception e) {
    }

    return invalidFile;
}
