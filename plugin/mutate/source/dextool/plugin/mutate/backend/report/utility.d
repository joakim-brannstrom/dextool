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

void reportStatistics(ReportT)(ref Database db, const Mutation.Kind[] kinds, ref ReportT item) @safe nothrow {
    import core.time : dur;
    import std.algorithm : map, filter, sum;
    import std.range : only;
    import std.datetime : Clock;
    import dextool.plugin.mutate.backend.utility;

    auto alive = db.aliveMutants(kinds);
    auto killed = db.killedMutants(kinds);
    auto timeout = db.timeoutMutants(kinds);
    auto untested = db.unknownMutants(kinds);
    auto killed_by_compiler = db.killedByCompilerMutants(kinds);

    try {
        immutable align_ = 8;

        const auto total_time = only(alive, killed, timeout).filter!(a => !a.isNull)
            .map!(a => a.time.total!"msecs").sum.dur!"msecs";
        const auto total_cnt = only(alive, killed, timeout).filter!(a => !a.isNull)
            .map!(a => a.count).sum;
        const auto killed_cnt = only(killed, timeout).filter!(a => !a.isNull)
            .map!(a => a.count).sum;
        const auto untested_cnt = untested.isNull ? 0 : untested.count;
        const auto predicted = total_cnt > 0 ? (untested_cnt * (total_time / total_cnt))
            : 0.dur!"msecs";

        // execution time
        if (untested_cnt > 0 && predicted > 0.dur!"msecs")
            item.writefln("Predicted time until mutation testing is done: %s (%s)",
                    predicted, Clock.currTime + predicted);
        item.writefln("%-*s %s", align_ * 4, "Mutation execution time:", total_time);
        if (!killed_by_compiler.isNull)
            item.tracef("%-*s %s", align_ * 4, "Mutants killed by compiler:",
                    killed_by_compiler.time);

        item.writeln("");

        // mutation score and details
        if (!untested.isNull && untested.count > 0)
            item.writefln("Untested: %s", untested.count);
        if (!alive.isNull)
            item.writefln("%-*s %s", align_, "Alive:", alive.count);
        if (!killed.isNull)
            item.writefln("%-*s %s", align_, "Killed:", killed.count);
        if (!timeout.isNull)
            item.writefln("%-*s %s", align_, "Timeout:", timeout.count);
        item.writefln("%-*s %s", align_, "Total:", total_cnt);
        if (total_cnt > 0)
            item.writefln("%-*s %s", align_, "Score:",
                    cast(double) killed_cnt / cast(double) total_cnt);
        if (!killed_by_compiler.isNull)
            item.tracef("%-*s %s", align_, "Killed by compiler:", killed_by_compiler.count);
    }
    catch (Exception e) {
        logger.warning(e.msg).collectException;
    }
}

void reportMutationSubtypeStats(ReportT)(
        ref const long[MakeMutationTextResult] mut_stat, ref ReportT item, const int align_) @safe nothrow {
    import std.algorithm : sum, map, sort, filter;

    // trusted because it is @safe in dmd-2.078.1
    // TODO remove the trusted wrapper
    long total = () @trusted{ return mut_stat.byValue.sum; }();

    import std.array : array;
    import std.range : take;
    import std.typecons : Tuple;

    // trusted because it is marked as @safe in dmd-2.078.1
    // TODO remove this trusted when upgrading the minimal compiler
    // can be simplified to:
    // foreach (v, alive.byKeyValue.array.sort!((a, b) => a.value > b.value))....
    auto kv = () @trusted{
        return mut_stat.byKeyValue.array.sort!((a, b) => a.value > b.value)
            .take(20).map!(a => Tuple!(MakeMutationTextResult, "key", long,
                    "value")(a.key, a.value)).array;
    }();

    foreach (v; kv) {
        try {
            auto percentage = (cast(double) v.value / cast(double) total) * 100.0;

            item.writefln("%-*s %-*s '%s' to '%s'", align_, percentage, align_,
                    v.value, window(v.key.original, windowSize),
                    window(v.key.mutation, windowSize));
        }
        catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }
}
