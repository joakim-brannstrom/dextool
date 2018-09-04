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

import dextool.plugin.mutate.backend.type : Mutation, Offset, TestCase,
    Language;
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

    bool opEquals(const typeof(this) o) const nothrow @safe {
        return original == o.original && mutation == o.mutation;
    }
}

auto makeMutationText(SafeInput file_, const Offset offs, Mutation.Kind kind, Language lang) nothrow {
    import dextool.plugin.mutate.backend.generate_mutant : makeMutation;

    MakeMutationTextResult rval;

    try {
        if (offs.end < file_.read.length) {
            rval.original = file_.read[offs.begin .. offs.end].toInternal;
        }

        auto mut = makeMutation(kind, lang);
        rval.mutation = mut.mutate(rval.original);
    } catch (Exception e) {
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
    } catch (Exception e) {
    }

    return invalidFile;
}

void reportMutationSubtypeStats(ref const long[MakeMutationTextResult] mut_stat, ref Table!4 tbl) @safe nothrow {
    import std.conv : to;
    import std.format : format;
    import std.algorithm : sum, map, sort, filter;

    long total = mut_stat.byValue.sum;

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

            // dfmt off
            typeof(tbl).Row r = [
                percentage.to!string,
                v.value.to!string,
                format("`%s`", window(v.key.original, windowSize)),
                format("`%s`", window(v.key.mutation, windowSize)),
            ];
            // dfmt on
            tbl.put(r);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }
}

/** Update the table with the score of test cases and how many mutants they killed.
 *
 * Params:
 *  mut_stat = holder of the raw statistics data to derive the mapping from
 *  total = total number of mutants
 *  take_ = how many from the top should be moved to the table
 *  tbl = table to write the data to
 */
void reportTestCaseStats(ref const long[TestCase] mut_stat, const long total,
        const long take_, ref Table!3 tbl) @safe nothrow {
    import std.algorithm : sort;
    import std.array : array;
    import std.conv : to;
    import std.range : take;

    static bool cmp(T)(ref T a, ref T b) {
        if (a.value > b.value)
            return true;
        else if (a.value < b.value)
            return false;
        else if (a.key > b.key)
            return true;
        else if (a.key < b.key)
            return false;
        return false;
    }

    foreach (v; mut_stat.byKeyValue.array.sort!cmp.take(take_)) {
        try {
            auto percentage = (cast(double) v.value / cast(double) total) * 100.0;
            typeof(tbl).Row r = [percentage.to!string, v.value.to!string, v.key.toString];
            tbl.put(r);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }
}

/** Update the table with those test cases that has killed zero mutants.
 */
void reportDeadTestCases(TestCase[] zero_kills_test_cases, ref Table!1 tbl) @safe nothrow {
    foreach (tc; zero_kills_test_cases) {
        typeof(tbl).Row r = [tc.toString];
        tbl.put(r);
    }
}

import dextool.plugin.mutate.backend.database : MutationId;

/// Information needed to present the mutant to an user.
struct MutationRepr {
    import dextool.type : Path;
    import dextool.plugin.mutate.backend.type : SourceLoc;

    SourceLoc sloc;
    Path file;
    MakeMutationTextResult mutation;
}

alias Mutations = bool[MutationId];
alias MutationsMap = Mutations[TestCase];
alias MutationReprMap = MutationRepr[MutationId];

void reportTestCaseKillMap(WriterTextT, WriterT)(ref const MutationsMap mut_stat,
        ref const MutationReprMap mutrepr, WriterTextT writer_txt, WriterT writer) @safe {
    import std.conv : to;
    import std.range : put;
    import std.format : format;

    alias MutTable = Table!4;
    alias Row = MutTable.Row;

    foreach (tc_muts; mut_stat.byKeyValue) {
        put(writer_txt, tc_muts.key.toString);

        MutTable tbl;
        tbl.heading = ["ID", "File Line:Column", "From", "To"];

        foreach (mut; tc_muts.value.byKey) {
            Row row;

            if (auto v = mut in mutrepr) {
                row[1] = format("%s %s:%s", v.file, v.sloc.line, v.sloc.column);
                row[2] = format("`%s`", window(v.mutation.original, windowSize));
                row[3] = format("`%s`", window(v.mutation.mutation, windowSize));
            }

            row[0] = mut.to!string;
            tbl.put(row);
        }

        put(writer, tbl);
    }
}

void reportMutationTestCaseSuggestion(WriterT)(ref Database db,
        const MutationId[] tc_sugg, WriterT writer) @safe {
    import std.conv : to;
    import std.range : put;
    import std.format : format;

    alias MutTable = Table!1;
    alias Row = MutTable.Row;

    foreach (mut_id; tc_sugg) {
        MutTable tbl;
        tbl.heading = [mut_id.to!string];

        try {
            auto suggestions = db.getSurroundingTestCases(mut_id);
            if (suggestions.length == 0)
                continue;

            foreach (tc; suggestions) {
                Row row;
                row[0] = format("`%s`", tc);
                tbl.put(row);
            }
            put(writer, tbl);
        } catch (Exception e) {
            logger.warning(e.msg);
        }
    }
}

void reportStatistics(ReportT)(ref Database db, const Mutation.Kind[] kinds, ref ReportT item) @safe nothrow {
    import core.time : dur;
    import std.algorithm : map, filter, sum;
    import std.range : only;
    import std.datetime : Clock;
    import dextool.plugin.mutate.backend.utility;

    const alive = db.aliveMutants(kinds);
    const killed = db.killedMutants(kinds);
    const timeout = db.timeoutMutants(kinds);
    const untested = db.unknownMutants(kinds);
    const killed_by_compiler = db.killedByCompilerMutants(kinds);
    const total = db.totalMutants(kinds);

    try {
        immutable align_ = 8;

        const total_time = total.isNull ? 0.dur!"msecs" : total.time;
        const total_cnt = total.isNull ? 0 : total.count;
        const killed_cnt = only(killed, timeout).filter!(a => !a.isNull)
            .map!(a => a.count)
            .sum;
        const untested_cnt = untested.isNull ? 0 : untested.count;
        const predicted = total_cnt > 0 ? (untested_cnt * (total_time / total_cnt)) : 0
            .dur!"msecs";

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
    } catch (Exception e) {
        logger.warning(e.msg).collectException;
    }
}

struct Table(int columnsNr) {
    alias Row = string[columnsNr];

    Row heading_;
    Row[] rows;
    ulong[columnsNr] columnWidth;

    this(const Row heading) {
        this.heading = heading;
        updateColumns(heading);
    }

    void heading(const Row r) {
        heading_ = r;
        updateColumns(r);
    }

    void put(const Row r) {
        rows ~= r;
        updateColumns(r);
    }

    import std.format : FormatSpec;

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        import std.ascii : newline;
        import std.range : enumerate, repeat;
        import std.format : formattedWrite;
        import std.range.primitives : put;

        immutable sep = "|";
        immutable lhs_sep = "| ";
        immutable mid_sep = " | ";
        immutable rhs_sep = " |";

        void printRow(const ref Row r) {
            foreach (const r_; r[].enumerate) {
                if (r_.index == 0)
                    put(w, lhs_sep);
                else
                    put(w, mid_sep);
                formattedWrite(w, "%-*s", columnWidth[r_.index], r_.value);
            }
            put(w, rhs_sep);
            put(w, newline);
        }

        printRow(heading_);

        immutable dash = "-";
        foreach (len; columnWidth) {
            put(w, sep);
            put(w, repeat(dash, len + 2));
        }
        put(w, sep);
        put(w, newline);

        foreach (const ref r; rows) {
            printRow(r);
        }
    }

    private void updateColumns(const ref Row r) {
        import std.algorithm : filter, count, map;
        import std.range : enumerate;
        import std.utf : byCodeUnit;
        import std.typecons : tuple;

        foreach (a; r[].enumerate
                .map!(a => tuple(a.index, a.value.byCodeUnit.count))
                .filter!(a => a[1] > columnWidth[a[0]])) {
            columnWidth[a[0]] = a[1];
        }
    }
}
