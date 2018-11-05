/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.utility;

import logger = std.experimental.logger;
import std.exception : collectException;
import std.typecons : Flag, Yes, No;

import dextool.plugin.mutate.backend.database : Database, spinSqlQuery,
    MutationId;
import dextool.plugin.mutate.backend.interface_ : FilesysIO, SafeInput;
import dextool.plugin.mutate.backend.type : Mutation, Offset, TestCase,
    Language, TestGroup;
import dextool.plugin.mutate.type : ReportKillSortOrder;
import dextool.plugin.mutate.type : ReportLevel, ReportSection;
import dextool.type;

public import dextool.plugin.mutate.backend.utility : MakeMutationTextResult,
    makeMutationText;

// 5 because it covers all the operators and true/false
immutable windowSize = 5;

immutable invalidFile = "Dextool: Invalid UTF-8 content";

@safe:

/// Create a range from `a` that has at most maxlen+3 letters in it.
auto window(T)(T a, size_t maxlen) {
    import std.algorithm : filter, among, joiner;
    import std.range : take, only, chain;

    // dfmt off
    return chain(a.take(maxlen).filter!(a => !a.among('\n')),
                 only(a.length > maxlen ? "..." : null).joiner);
    // dfmt on
}

ReportSection[] toSections(const ReportLevel l) {
    ReportSection[] secs;
    final switch (l) with (ReportSection) {
    case ReportLevel.summary:
        secs = [summary, mut_stat];
        break;
    case ReportLevel.alive:
        secs = [summary, mut_stat, tc_killed_no_mutants, tc_full_overlap, alive];
        break;
    case ReportLevel.all:
        secs = [summary, mut_stat, all_mut, tc_killed,
            tc_killed_no_mutants, tc_full_overlap];
        break;
    }

    return secs;
}

string toInternal(ubyte[] data) @safe nothrow {
    import std.utf : validate;

    try {
        auto result = () @trusted { return cast(string) data; }();
        validate(result);
        return result;
    } catch (Exception e) {
    }

    return invalidFile;
}

void reportMutationSubtypeStats(ref const long[MakeMutationTextResult] mut_stat, ref Table!4 tbl) @safe nothrow {
    import std.algorithm : sum, map, sort, filter;
    import std.array : array;
    import std.conv : to;
    import std.format : format;
    import std.range : take;

    long total = mut_stat.byValue.sum;

    foreach (v; mut_stat.byKeyValue.array.sort!((a, b) => a.value > b.value).take(20)) {
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
        const long take_, const ReportKillSortOrder sort_order, ref Table!4 tbl) @safe nothrow {
    import std.algorithm : sort;
    import std.array : array;
    import std.conv : to;
    import std.range : take, retro;

    // nothing to do. this also ensure that we do not divide by zero.
    if (total == 0)
        return;

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

    auto takeOrder(RangeT)(RangeT range) {
        final switch (sort_order) {
        case ReportKillSortOrder.top:
            return range.take(take_).array;
        case ReportKillSortOrder.bottom:
            return range.array.retro.take(take_).array;
        }
    }

    foreach (v; takeOrder(mut_stat.byKeyValue.array.sort!cmp)) {
        try {
            auto percentage = (cast(double) v.value / cast(double) total) * 100.0;
            typeof(tbl).Row r = [
                percentage.to!string, v.value.to!string, v.key.name, v.key.location
            ];
            tbl.put(r);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }
}

/// Statistics about dead test cases.
struct TestCaseDeadStat {
    import std.range : isOutputRange;

    /// The ratio of dead TC of the total.
    double ratio;
    TestCase[] testCases;
    long total;

    long numDeadTC() @safe pure nothrow const @nogc scope {
        return testCases.length;
    }

    string toString() @safe const {
        import std.array : appender;

        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) @safe const 
            if (isOutputRange!(Writer, char)) {
        import std.ascii : newline;
        import std.format : formattedWrite;
        import std.range : put;

        if (total > 0)
            formattedWrite(w, "%s/%s = %s of all test cases\n", numDeadTC, total, ratio);
        foreach (tc; testCases) {
            put(w, tc.name);
            if (tc.location.length > 0) {
                put(w, " | ");
                put(w, tc.location);
            }
            put(w, newline);
        }
    }
}

void toTable(ref TestCaseDeadStat st, ref Table!2 tbl) @safe pure nothrow {
    foreach (tc; st.testCases) {
        typeof(tbl).Row r = [tc.name, tc.location];
        tbl.put(r);
    }
}

/** Returns: report of test cases that has killed zero mutants.
 */
TestCaseDeadStat reportDeadTestCases(ref Database db) @safe {
    TestCaseDeadStat r;
    r.total = db.getNumOfTestCases;
    r.testCases = db.getTestCasesWithZeroKills;
    if (r.total > 0)
        r.ratio = cast(double) r.numDeadTC / cast(double) r.total;
    return r;
}

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

/// Statistics for a group of mutants.
struct MutationStat {
    import core.time : Duration;
    import std.range : isOutputRange;

    // TODO: use MutationScore instead
    long alive;
    long killed;
    long timeout;
    long untested;
    long killedByCompiler;
    long total;

    Duration totalTime;
    Duration killedByCompilerTime;
    Duration predictedDone;

    double score() @safe pure nothrow const @nogc {
        if (total > 0)
            return cast(double)(killed + timeout) / cast(double) total;
        return 1.0;
    }

    string toString() @safe const {
        import std.array : appender;

        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        import core.time : dur;
        import std.ascii : newline;
        import std.datetime : Clock;
        import std.format : formattedWrite;
        import std.range : put;
        import dextool.plugin.mutate.backend.utility;

        immutable align_ = 8;

        // execution time
        if (untested > 0 && predictedDone > 0.dur!"msecs")
            formattedWrite(w, "Predicted time until mutation testing is done: %s (%s)\n",
                    predictedDone, Clock.currTime + predictedDone);
        formattedWrite(w, "%-*s %s\n", align_ * 4, "Mutation execution time:", totalTime);
        if (killedByCompiler > 0)
            formattedWrite(w, "%-*s %s\n", align_ * 4,
                    "Mutants killed by compiler:", killedByCompilerTime);
        put(w, newline);

        // mutation score and details
        if (untested > 0)
            formattedWrite(w, "Untested: %s\n", untested);
        formattedWrite(w, "%-*s %s\n", align_, "Alive:", alive);
        formattedWrite(w, "%-*s %s\n", align_, "Killed:", killed);
        formattedWrite(w, "%-*s %s\n", align_, "Timeout:", timeout);
        formattedWrite(w, "%-*s %s\n", align_, "Total:", total);
        formattedWrite(w, "%-*s %s\n", align_, "Score:", score);
        formattedWrite(w, "%-*s %s\n", align_, "Killed by compiler:", killedByCompiler);
    }
}

MutationStat reportStatistics(ref Database db, const Mutation.Kind[] kinds) @safe nothrow {
    import core.time : dur;
    import std.algorithm : map, sum;
    import std.range : only;
    import dextool.plugin.mutate.backend.utility;

    const alive = spinSqlQuery!(() { return db.aliveSrcMutants(kinds); });
    const killed = spinSqlQuery!(() { return db.killedSrcMutants(kinds); });
    const timeout = spinSqlQuery!(() { return db.timeoutSrcMutants(kinds); });
    const untested = spinSqlQuery!(() { return db.unknownSrcMutants(kinds); });
    const killed_by_compiler = spinSqlQuery!(() {
        return db.killedByCompilerSrcMutants(kinds);
    });
    const total = spinSqlQuery!(() { return db.totalSrcMutants(kinds); });

    MutationStat st;
    st.alive = alive.count;
    st.killed = only(killed, timeout).map!(a => a.count).sum;
    st.timeout = timeout.count;
    st.untested = untested.count;
    st.total = total.count;
    st.totalTime = total.time;
    st.predictedDone = st.total > 0 ? (st.untested * (st.totalTime / st.total)) : 0.dur!"msecs";
    st.killedByCompilerTime = killed_by_compiler.time;

    return st;
}

struct TestCaseOverlapStat {
    import std.format : formattedWrite, format;
    import std.range : put;
    import dextool.hash;
    import dextool.plugin.mutate.backend.database.type : TestCaseId;

    long overlap;
    long total;
    double ratio;

    // map between test cases and the mutants they have killed.
    TestCaseId[][Murmur3] tc_mut;
    // map between mutation IDs and the test cases that killed them.
    long[][Murmur3] mutid_mut;
    string[TestCaseId] name_tc;

    string sumToString() @safe const {
        return format("%s/%s = %s test cases", overlap, total, ratio);
    }

    void sumToString(Writer)(ref Writer w) @safe const {
        formattedWrite(w, "%s/%s = %s test cases\n", overlap, total, ratio);
    }

    string toString() @safe const {
        import std.array : appender;

        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) @safe const {
        import std.algorithm : sort, map, filter, count;
        import std.array : array;

        sumToString(w);

        foreach (tcs; tc_mut.byKeyValue.filter!(a => a.value.length > 1)) {
            bool first = true;
            // TODO this is a bit slow. use a DB row iterator instead.
            foreach (name; tcs.value.map!(id => name_tc[id])) {
                if (first) {
                    formattedWrite(w, "%s %s\n", name, mutid_mut[tcs.key].length);
                    first = false;
                } else {
                    formattedWrite(w, "%s\n", name);
                }
            }
            put(w, "\n");
        }
    }
}

/** Report test cases that completly overlap each other.
 *
 * Returns: a string with statistics.
 */
template toTable(Flag!"colWithMutants" colMutants) {
    static if (colMutants) {
        alias TableT = Table!3;
    } else {
        alias TableT = Table!2;
    }
    alias RowT = TableT.Row;

    void toTable(ref TestCaseOverlapStat st, ref TableT tbl) {
        import std.algorithm : sort, map, filter, count;
        import std.array : array;
        import std.conv : to;
        import std.format : format;

        foreach (tcs; st.tc_mut.byKeyValue.filter!(a => a.value.length > 1)) {
            bool first = true;
            // TODO this is a bit slow. use a DB row iterator instead.
            foreach (name; tcs.value.map!(id => st.name_tc[id])) {
                RowT r;
                r[0] = name;
                if (first) {
                    auto muts = st.mutid_mut[tcs.key];
                    r[1] = muts.length.to!string;
                    static if (colMutants) {
                        r[2] = format("%-(%s,%)", muts);
                    }
                    first = false;
                }

                tbl.put(r);
            }
            static if (colMutants)
                RowT r = ["", "", ""];
            else
                RowT r = ["", ""];
            tbl.put(r);
        }
    }
}

/// Test cases that kill exactly the same mutants.
TestCaseOverlapStat reportTestCaseFullOverlap(ref Database db, const Mutation.Kind[] kinds) @safe {
    import std.algorithm : sort, map, filter, count;
    import std.array : array;
    import dextool.hash;
    import dextool.plugin.mutate.backend.database.type : TestCaseId;

    TestCaseOverlapStat st;
    st.total = db.getNumOfTestCases;

    foreach (tc_id; db.getTestCasesWithAtLeastOneKill(kinds)) {
        auto muts = db.getTestCaseMutantKills(tc_id, kinds).sort.map!(a => cast(long) a).array;
        auto m3 = makeMurmur3(cast(ubyte[]) muts);
        if (auto v = m3 in st.tc_mut)
            (*v) ~= tc_id;
        else {
            st.tc_mut[m3] = [tc_id];
            st.mutid_mut[m3] = muts;
        }
        st.name_tc[tc_id] = db.getTestCaseName(tc_id);
    }

    foreach (tcs; st.tc_mut.byKeyValue.filter!(a => a.value.length > 1)) {
        st.overlap += tcs.value.count;
    }

    if (st.total > 0)
        st.ratio = cast(double) st.overlap / cast(double) st.total;

    return st;
}

struct TestGroupStats {
    static struct Mutant {
        MutationId id;
        Path path;
    }

    /// Statistics for a test group.
    MutationStat[string] stats;
    /// Map between test cases and their test group.
    TestCase[][string] testCases_group;
    /// Mutation ID's that are alive in a test group
    Mutant[][string] aliveMutants;
    /// Description
    string[string] description;
    /// Files with mutants that this test group has killed
    string[][string] files;
}

TestGroupStats reportTestGroups(ref Database db, const Mutation.Kind[] kinds, const(TestGroup)[] tgs) @safe {
    import std.algorithm : filter, map;
    import std.typecons : tuple;
    import std.array : appender;
    import dextool.plugin.mutate.backend.database : MutationStatusId;
    import dextool.set;

    static struct TcStat {
        Set!MutationStatusId alive;
        Set!MutationStatusId killed;
        Set!MutationStatusId timeout;
        Set!MutationStatusId total;
    }

    TestGroupStats r;
    TcStat[string] tcg_stat;

    foreach (a; tgs) {
        r.stats[a.name] = MutationStat.init;
        r.description[a.name] = a.description;
        tcg_stat[a.name] = TcStat.init;
    }

    // map test cases to their group
    foreach (tc; db.getDetectedTestCases) {
        foreach (ref g; tgs) {
            import std.regex : matchFirst;

            auto m = matchFirst(tc.name, g.re);
            // the regex must match the full test case thus checking that
            // nothing is left before or after
            if (!m.empty && m.pre.length == 0 && m.post.length == 0) {
                r.testCases_group[g.name] ~= tc;
            }
        }
    }

    // collect mutation statistics for each test case group
    foreach (ref const tcg; r.testCases_group.byKeyValue) {
        Set!string files;
        foreach (const tc; tcg.value) {
            auto v = tcg.key in tcg_stat;
            foreach (const id; db.testCaseMutationPointAliveSrcMutants(kinds, tc))
                v.alive.add(id);
            foreach (const id; db.testCaseMutationPointKilledSrcMutants(kinds, tc))
                v.killed.add(id);
            foreach (const id; db.testCaseMutationPointTimeoutSrcMutants(kinds, tc))
                v.timeout.add(id);
            foreach (const id; db.testCaseMutationPointTotalSrcMutants(kinds, tc))
                v.total.add(id);

            // TODO: this is slow.....
            // store files that this test group killed mutants in
            foreach (const p; db.getMutationIds(db.testCaseKilledSrcMutants(kinds,
                    tc)).map!(a => db.getPath(a))) {
                files.add(p);
            }
        }
        r.files[tcg.key] = files.setToList!string;
    }

    // store the alive mutants
    foreach (ref const tcg; tcg_stat.byKeyValue) {
        auto ids = db.getMutationIds(tcg.value.alive.setToList!MutationStatusId);
        auto app = appender!(TestGroupStats.Mutant[])();
        foreach (id; db.getMutationIds(tcg.value.alive.setToList!MutationStatusId)) {
            app.put(TestGroupStats.Mutant(id, db.getPath(id)));
        }
        r.aliveMutants[tcg.key] = app.data;
    }

    // update the mutation stat for the test case group
    foreach (ref tcg; r.stats.byKeyValue) {
        auto v = tcg.key in tcg_stat;
        tcg.value.alive = v.alive.length;
        tcg.value.killed = v.killed.length;
        tcg.value.timeout = v.timeout.length;
        tcg.value.total = v.total.length;
    }

    return r;
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

    bool empty() @safe pure nothrow const @nogc {
        return rows.length == 0;
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
