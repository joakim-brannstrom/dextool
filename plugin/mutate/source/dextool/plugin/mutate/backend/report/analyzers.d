/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains different kinds of report methods and statistical
analyzers of the data gathered in the database.
*/
module dextool.plugin.mutate.backend.report.analyzers;

import logger = std.experimental.logger;
import std.algorithm : sum, map, sort, filter, count, cmp, joiner;
import std.array : array, appender;
import std.conv : to;
import std.exception : collectException;
import std.format : format;
import std.range : take, retro, only;
import std.typecons : Flag, Yes, No, Tuple, Nullable, tuple;

import dextool.plugin.mutate.backend.database : Database, spinSql, MutationId, MarkedMutant;
import dextool.plugin.mutate.backend.diff_parser : Diff;
import dextool.plugin.mutate.backend.generate_mutant : MakeMutationTextResult,
    makeMutationText, makeMutation;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.report.utility : window, windowSize,
    statusToString, kindToString;
import dextool.plugin.mutate.backend.type : Mutation, Offset, TestCase, TestGroup;
import dextool.plugin.mutate.type : ReportKillSortOrder;
import dextool.plugin.mutate.type : ReportLevel, ReportSection;
import dextool.type;

public import dextool.plugin.mutate.backend.report.utility : Table;

@safe:

void reportMutationSubtypeStats(ref const long[MakeMutationTextResult] mut_stat, ref Table!4 tbl) @safe nothrow {
    auto profile = Profile(ReportSection.mut_stat);

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
 *  db = ?
 *  kinds = type of mutants to count for the test case
 *  take_ = how many from the top should be moved to the table
 *  sort_order = ctrl if the top or bottom of the test cases should be reported
 *  tbl = table to write the data to
 */
void reportTestCaseStats(ref Database db, const Mutation.Kind[] kinds,
        const long take_, const ReportKillSortOrder sort_order, ref Table!3 tbl) @safe nothrow {
    import dextool.plugin.mutate.backend.database.type : TestCaseInfo;

    auto profile = Profile(ReportSection.tc_stat);

    alias TcInfo = Tuple!(string, "name", TestCaseInfo, "tc");

    const total = spinSql!(() { return db.totalMutants(kinds).count; });

    // nothing to do. this also ensure that we do not divide by zero.
    if (total == 0)
        return;

    static bool cmp(T)(ref T a, ref T b) {
        if (a.tc.killedMutants > b.tc.killedMutants)
            return true;
        else if (a.tc.killedMutants < b.tc.killedMutants)
            return false;
        else if (a.name > b.name)
            return true;
        else if (a.name < b.name)
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

    const test_cases = spinSql!(() { return db.getDetectedTestCases; });

    foreach (v; takeOrder(test_cases.map!(a => TcInfo(a.name, spinSql!(() {
                return db.getTestCaseInfo(a, kinds);
            })))
            .array
            .sort!cmp)) {
        try {
            auto percentage = (cast(double) v.tc.killedMutants / cast(double) total) * 100.0;
            typeof(tbl).Row r = [
                percentage.to!string, v.tc.killedMutants.to!string, v.name
            ];
            tbl.put(r);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }
}

/** The result of analysing the test cases to see how similare they are to each
 * other.
 */
class TestCaseSimilarityAnalyse {
    import dextool.plugin.mutate.backend.type : TestCase;

    static struct Similarity {
        TestCase testCase;
        double similarity;
        /// Mutants that are similare between `testCase` and the parent.
        MutationId[] intersection;
        /// Unique mutants that are NOT verified by `testCase`.
        MutationId[] difference;
    }

    Similarity[][TestCase] similarities;
}

/// The result of the similarity analyse
private struct Similarity {
    /// The quota |A intersect B| / |A|. Thus it is how similare A is to B. If
    /// B ever fully encloses A then the score is 1.0.
    double similarity;
    MutationId[] intersection;
    MutationId[] difference;
}

// The set similairty measures how much of lhs is in rhs. This is a
// directional metric.
private Similarity setSimilarity(MutationId[] lhs_, MutationId[] rhs_) {
    import dextool.set;

    auto lhs = lhs_.toSet;
    auto rhs = rhs_.toSet;
    auto intersect = lhs.intersect(rhs);
    auto diff = lhs.setDifference(rhs);
    return Similarity(cast(double) intersect.length / cast(double) lhs.length,
            intersect.toArray, diff.toArray);
}

/** Analyse the similarity between test cases.
 *
 * TODO: the algorithm used is slow. Maybe matrix representation and sorted is better?
 *
 * Params:
 *  db = ?
 *  kinds = mutation kinds to use in the distance analyze
 *  limit = limit the number of test cases to the top `limit`.
 */
TestCaseSimilarityAnalyse reportTestCaseSimilarityAnalyse(ref Database db,
        const Mutation.Kind[] kinds, ulong limit) @safe {
    import std.container.binaryheap;
    import dextool.plugin.mutate.backend.database.type : TestCaseInfo, TestCaseId;

    auto profile = Profile(ReportSection.tc_similarity);

    // TODO: reduce the code duplication of the caches.
    // The DB lookups must be cached or otherwise the algorithm becomes too
    // slow for practical use.

    MutationId[][TestCaseId] kill_cache2;
    MutationId[] getKills(TestCaseId id) @trusted {
        return kill_cache2.require(id, spinSql!(() {
                return db.getTestCaseMutantKills(id, kinds);
            }));
    }

    TestCase[TestCaseId] tc_cache2;
    TestCase getTestCase(TestCaseId id) @trusted {
        return tc_cache2.require(id, spinSql!(() {
                // assuming it can never be null
                return db.getTestCase(id).get;
            }));
    }

    alias TcKills = Tuple!(TestCaseId, "id", MutationId[], "kills");

    const test_cases = spinSql!(() { return db.getDetectedTestCaseIds; });

    auto rval = new typeof(return);

    foreach (tc_kill; test_cases.map!(a => TcKills(a, getKills(a)))
            .filter!(a => a.kills.length != 0)) {
        auto app = appender!(TestCaseSimilarityAnalyse.Similarity[])();
        foreach (tc; test_cases.filter!(a => a != tc_kill.id)
                .map!(a => TcKills(a, getKills(a)))
                .filter!(a => a.kills.length != 0)) {
            auto distance = setSimilarity(tc_kill.kills, tc.kills);
            if (distance.similarity > 0)
                app.put(TestCaseSimilarityAnalyse.Similarity(getTestCase(tc.id),
                        distance.similarity, distance.intersection, distance.difference));
        }
        if (app.data.length != 0) {
            () @trusted {
                rval.similarities[getTestCase(tc_kill.id)] = heapify!((a,
                        b) => a.similarity < b.similarity)(app.data).take(limit).array;
            }();
        }
    }

    return rval;
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
    auto profile = Profile(ReportSection.tc_killed_no_mutants);

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
    import std.range : put;

    auto profile = Profile(ReportSection.tc_map);

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
    import std.range : put;

    auto profile = Profile(ReportSection.tc_suggestion);

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

    long alive;
    // Nr of mutants that are alive but tagged with nomut.
    long aliveNoMut;
    long killed;
    long timeout;
    long untested;
    long killedByCompiler;
    long total;

    Duration totalTime;
    Duration killedByCompilerTime;
    Duration predictedDone;

    /// Adjust the score with the alive mutants that are suppressed.
    double score() @safe pure nothrow const @nogc {
        if (total > 0)
            return cast(double)(killed + timeout) / cast(double)(total - aliveNoMut);
        if (untested > 0)
            return 0.0;
        return 1.0;
    }

    /// Suppressed mutants of the total mutants.
    double suppressedOfTotal() @safe pure nothrow const @nogc {
        if (total > 0)
            return (cast(double)(aliveNoMut) / cast(double) total);
        return 0.0;
    }

    string toString() @safe const {
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

        immutable align_ = 12;

        formattedWrite(w, "%-*s %s\n", align_, "Time spent:", totalTime);
        if (untested > 0 && predictedDone > 0.dur!"msecs") {
            const pred = Clock.currTime + predictedDone;
            formattedWrite(w, "Remaining: %s (%s)\n", predictedDone, pred.toISOExtString);
        }
        if (killedByCompiler > 0) {
            formattedWrite(w, "%-*s %s\n", align_ * 3,
                    "Time spent on mutants killed by compiler:", killedByCompilerTime);
        }

        put(w, newline);

        // mutation score and details
        formattedWrite(w, "%-*s %.3s\n", align_, "Score:", score);
        formattedWrite(w, "%-*s %s\n", align_, "Total:", total);
        if (untested > 0) {
            formattedWrite(w, "%-*s %s\n", align_, "Untested:", untested);
        }
        formattedWrite(w, "%-*s %s\n", align_, "Alive:", alive);
        formattedWrite(w, "%-*s %s\n", align_, "Killed:", killed);
        formattedWrite(w, "%-*s %s\n", align_, "Timeout:", timeout);
        formattedWrite(w, "%-*s %s\n", align_, "Killed by compiler:", killedByCompiler);

        if (aliveNoMut != 0)
            formattedWrite(w, "%-*s %s (%.3s)\n", align_,
                    "Suppressed (nomut):", aliveNoMut, suppressedOfTotal);
    }
}

MutationStat reportStatistics(ref Database db, const Mutation.Kind[] kinds, string file = null) @safe nothrow {
    import core.time : dur;
    import dextool.plugin.mutate.backend.utility;

    auto profile = Profile(ReportSection.summary);

    const alive = spinSql!(() { return db.aliveSrcMutants(kinds, file); });
    const alive_nomut = spinSql!(() {
        return db.aliveNoMutSrcMutants(kinds, file);
    });
    const killed = spinSql!(() { return db.killedSrcMutants(kinds, file); });
    const timeout = spinSql!(() { return db.timeoutSrcMutants(kinds, file); });
    const untested = spinSql!(() { return db.unknownSrcMutants(kinds, file); });
    const killed_by_compiler = spinSql!(() {
        return db.killedByCompilerSrcMutants(kinds, file);
    });
    const total = spinSql!(() { return db.totalSrcMutants(kinds, file); });

    MutationStat st;
    st.alive = alive.count;
    st.aliveNoMut = alive_nomut.count;
    st.killed = killed.count;
    st.timeout = timeout.count;
    st.untested = untested.count;
    st.total = total.count;
    st.killedByCompiler = killed_by_compiler.count;

    st.totalTime = total.time;
    st.predictedDone = st.total > 0 ? (st.untested * (st.totalTime / st.total)) : 0.dur!"msecs";
    st.killedByCompilerTime = killed_by_compiler.time;

    return st;
}

struct MarkedMutantsStat {
    Table!6 tbl;
    // TODO: extend for html-report
}

MarkedMutantsStat reportMarkedMutants(ref Database db, const Mutation.Kind[] kinds, string file = null) @safe {
    MarkedMutantsStat st;
    st.tbl.heading = [
        "File", "Line", "Column", "Mutation", "Status", "Rationale"
    ];

    import std.conv : to;

    foreach (m; db.getMarkedMutants()) {
        typeof(st.tbl).Row r = [
            m.path, to!string(m.line), to!string(m.column), m.mutText, statusToString(m.toStatus), m.rationale
        ];
        st.tbl.put(r);
    }
    return st;
}

struct TestCaseOverlapStat {
    import std.format : formattedWrite;
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
        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) @safe const {
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
    import dextool.hash;
    import dextool.plugin.mutate.backend.database.type : TestCaseId;

    auto profile = Profile(ReportSection.tc_full_overlap);

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

class TestGroupSimilarity {
    static struct TestGroup {
        string description;
        string name;

        /// What the user configured as regex. Useful when e.g. generating reports
        /// for a user.
        string userInput;

        int opCmp(ref const TestGroup s) const {
            return cmp(name, s.name);
        }
    }

    static struct Similarity {
        /// The test group that the `key` is compared to.
        TestGroup comparedTo;
        /// How similare the `key` is to `comparedTo`.
        double similarity;
        /// Mutants that are similare between `testCase` and the parent.
        MutationId[] intersection;
        /// Unique mutants that are NOT verified by `testCase`.
        MutationId[] difference;
    }

    Similarity[][TestGroup] similarities;
}

/** Analyze the similarity between the test groups.
 *
 * Assuming that a limit on how many test groups to report isn't interesting
 * because they are few so it is never a problem.
 *
 */
TestGroupSimilarity reportTestGroupsSimilarity(ref Database db,
        const(Mutation.Kind)[] kinds, const(TestGroup)[] test_groups) @safe {
    import dextool.plugin.mutate.backend.database.type : TestCaseInfo, TestCaseId;

    auto profile = Profile(ReportSection.tc_groups_similarity);

    alias TgKills = Tuple!(TestGroupSimilarity.TestGroup, "testGroup", MutationId[], "kills");

    const test_cases = spinSql!(() { return db.getDetectedTestCaseIds; }).map!(
            a => Tuple!(TestCaseId, "id", TestCase, "tc")(a, spinSql!(() {
                return db.getTestCase(a);
            }))).array;

    MutationId[] gatherKilledMutants(const(TestGroup) tg) {
        auto kills = appender!(MutationId[])();
        foreach (tc; test_cases.filter!(a => a.tc.isTestCaseInTestGroup(tg.re))) {
            kills.put(spinSql!(() {
                    return db.getTestCaseMutantKills(tc.id, kinds);
                }));
        }
        return kills.data;
    }

    TgKills[] test_group_kills;
    foreach (const tg; test_groups) {
        auto kills = gatherKilledMutants(tg);
        if (kills.length != 0)
            test_group_kills ~= TgKills(TestGroupSimilarity.TestGroup(tg.description,
                    tg.name, tg.userInput), kills);
    }

    // calculate similarity between all test groups.
    auto rval = new typeof(return);

    foreach (tg_parent; test_group_kills) {
        auto app = appender!(TestGroupSimilarity.Similarity[])();
        foreach (tg_other; test_group_kills.filter!(a => a.testGroup != tg_parent.testGroup)) {
            auto similarity = setSimilarity(tg_parent.kills, tg_other.kills);
            if (similarity.similarity > 0)
                app.put(TestGroupSimilarity.Similarity(tg_other.testGroup,
                        similarity.similarity, similarity.intersection, similarity.difference));
            if (app.data.length != 0)
                rval.similarities[tg_parent.testGroup] = app.data;
        }
    }

    return rval;
}

class TestGroupStat {
    import dextool.plugin.mutate.backend.database : MutationId, FileId, MutantInfo;

    /// Human readable description for the test group.
    string description;
    /// Statistics for a test group.
    MutationStat stats;
    /// Map between test cases and their test group.
    TestCase[] testCases;
    /// Lookup for converting a id to a filename
    Path[FileId] files;
    /// Mutants alive in a file.
    MutantInfo[][FileId] alive;
    /// Mutants killed in a file.
    MutantInfo[][FileId] killed;
}

import std.regex : Regex;

private bool isTestCaseInTestGroup(const TestCase tc, const Regex!char tg) {
    import std.regex : matchFirst;

    auto m = matchFirst(tc.name, tg);
    // the regex must match the full test case thus checking that
    // nothing is left before or after
    if (!m.empty && m.pre.length == 0 && m.post.length == 0) {
        return true;
    }
    return false;
}

TestGroupStat reportTestGroups(ref Database db, const(Mutation.Kind)[] kinds,
        const(TestGroup) test_g) @safe {
    import dextool.plugin.mutate.backend.database : MutationStatusId;
    import dextool.set;

    auto profile = Profile(ReportSection.tc_groups);

    static struct TcStat {
        Set!MutationStatusId alive;
        Set!MutationStatusId killed;
        Set!MutationStatusId timeout;
        Set!MutationStatusId total;

        // killed by the specific test case
        Set!MutationStatusId tcKilled;
    }

    auto r = new TestGroupStat;
    r.description = test_g.description;
    TcStat tc_stat;

    // map test cases to this test group
    foreach (tc; db.getDetectedTestCases) {
        if (tc.isTestCaseInTestGroup(test_g.re))
            r.testCases ~= tc;
    }

    // collect mutation statistics for each test case group
    foreach (const tc; r.testCases) {
        foreach (const id; db.testCaseMutationPointAliveSrcMutants(kinds, tc))
            tc_stat.alive.add(id);
        foreach (const id; db.testCaseMutationPointKilledSrcMutants(kinds, tc))
            tc_stat.killed.add(id);
        foreach (const id; db.testCaseMutationPointTimeoutSrcMutants(kinds, tc))
            tc_stat.timeout.add(id);
        foreach (const id; db.testCaseMutationPointTotalSrcMutants(kinds, tc))
            tc_stat.total.add(id);
        foreach (const id; db.testCaseKilledSrcMutants(kinds, tc))
            tc_stat.tcKilled.add(id);
    }

    // update the mutation stat for the test group
    r.stats.alive = tc_stat.alive.length;
    r.stats.killed = tc_stat.killed.length;
    r.stats.timeout = tc_stat.timeout.length;
    r.stats.total = tc_stat.total.length;

    // associate mutants with their file
    foreach (const m; db.getMutantsInfo(kinds, tc_stat.tcKilled.toArray)) {
        auto fid = db.getFileId(m.id);
        r.killed[fid.get] ~= m;

        if (fid.get !in r.files) {
            r.files[fid.get] = Path.init;
            r.files[fid.get] = db.getFile(fid.get);
        }
    }

    foreach (const m; db.getMutantsInfo(kinds, tc_stat.alive.toArray)) {
        auto fid = db.getFileId(m.id);
        r.alive[fid.get] ~= m;

        if (fid.get !in r.files) {
            r.files[fid.get] = Path.init;
            r.files[fid.get] = db.getFile(fid.get);
        }
    }

    return r;
}

/// High interest mutants.
class MutantSample {
    import dextool.plugin.mutate.backend.database : MutationId, FileId, MutantInfo,
        MutationStatus, MutationStatusId, MutationEntry, MutationStatusTime;

    MutationEntry[MutationStatusId] mutants;

    /// The mutant that had its status updated the furthest back in time.
    MutationStatusTime[] oldest;

    /// The mutant that has survived the longest in the system.
    MutationStatus[] hardestToKill;

    /// The latest mutants that where added and survived.
    MutationStatusTime[] latest;
}

/// Returns: samples of mutants that are of high interest to the user.
MutantSample reportSelectedAliveMutants(ref Database db,
        const(Mutation.Kind)[] kinds, long history_nr) {
    auto profile = Profile(ReportSection.mut_recommend_kill);

    auto rval = new typeof(return);

    rval.hardestToKill = db.getHardestToKillMutant(kinds, Mutation.Status.alive, history_nr);
    foreach (const mutst; rval.hardestToKill) {
        auto ids = db.getMutationIds(kinds, [mutst.statusId]);
        if (ids.length != 0)
            rval.mutants[mutst.statusId] = db.getMutation(ids[0]);
    }

    rval.oldest = db.getOldestMutants(kinds, history_nr);
    foreach (const mutst; rval.oldest) {
        auto ids = db.getMutationIds(kinds, [mutst.id]);
        if (ids.length != 0)
            rval.mutants[mutst.id] = db.getMutation(ids[0]);
    }

    return rval;
}

class DiffReport {
    import dextool.plugin.mutate.backend.database : FileId, MutantInfo;
    import dextool.plugin.mutate.backend.diff_parser : Diff;

    /// The mutation score.
    double score;

    /// The raw diff for a file
    Diff.Line[][FileId] rawDiff;

    /// Lookup for converting a id to a filename
    Path[FileId] files;
    /// Mutants alive in a file.
    MutantInfo[][FileId] alive;
    /// Mutants killed in a file.
    MutantInfo[][FileId] killed;
    /// Test cases that killed mutants.
    TestCase[] testCases;

    override string toString() @safe const {
        import std.format : formattedWrite;
        import std.range : put;

        auto w = appender!string;

        foreach (file; files.byKeyValue) {
            put(w, file.value);
            foreach (mut; alive[file.key])
                formattedWrite(w, "  %s\n", mut);
            foreach (mut; killed[file.key])
                formattedWrite(w, "  %s\n", mut);
        }

        formattedWrite(w, "Test Cases killing mutants");
        foreach (tc; testCases)
            formattedWrite(w, "  %s", tc);

        return w.data;
    }
}

DiffReport reportDiff(ref Database db, const(Mutation.Kind)[] kinds,
        ref Diff diff, AbsolutePath workdir) {
    import dextool.plugin.mutate.backend.database : MutationId, MutationStatusId;
    import dextool.plugin.mutate.backend.type : SourceLoc;
    import dextool.set;

    auto profile = Profile(ReportSection.diff);

    auto rval = new DiffReport;

    Set!MutationStatusId total;
    // used for deriving what test cases killed mutants in the diff.
    Set!MutationId killing_mutants;

    foreach (kv; diff.toRange(workdir)) {
        auto fid = db.getFileId(kv.key);
        if (fid.isNull) {
            logger.warning("This file in the diff has not been tested thus skipping it: ", kv.key);
            continue;
        }

        bool has_mutants;
        foreach (id; kv.value
                .toRange
                .map!(line => spinSql!(() => db.getMutationsOnLine(kinds,
                    fid.get, SourceLoc(line))))
                .joiner
                .filter!(id => id !in total)) {
            has_mutants = true;
            total.add(id);

            const info = db.getMutantsInfo(kinds, [id])[0];
            if (info.status == Mutation.Status.alive) {
                rval.alive[fid.get] ~= info;
            } else {
                rval.killed[fid.get] ~= info;
                killing_mutants.add(info.id);
            }
        }

        if (has_mutants) {
            rval.files[fid.get] = kv.key;
            rval.rawDiff[fid.get] = diff.rawDiff[kv.key];
        } else {
            logger.info("This file in the diff has no mutants on changed lines: ", kv.key);
        }
    }

    Set!TestCase test_cases;
    foreach (tc; killing_mutants.toRange.map!(a => db.getTestCases(a)).joiner)
        test_cases.add(tc);

    rval.testCases = test_cases.toArray.sort.array;

    if (total.length == 0) {
        rval.score = 1.0;
    } else {
        rval.score = cast(double) killing_mutants.length / cast(double) total.length;
    }

    return rval;
}

struct MinimalTestSet {
    import dextool.plugin.mutate.backend.database.type : TestCaseInfo;

    long total;

    /// Minimal set that achieve the mutation test score.
    TestCase[] minimalSet;
    /// Test cases that do not contribute to the mutation test score.
    TestCase[] redundant;
    /// Map between test case name and sum of all the test time of the mutants it killed.
    TestCaseInfo[string] testCaseTime;
}

MinimalTestSet reportMinimalSet(ref Database db, const Mutation.Kind[] kinds) {
    import dextool.plugin.mutate.backend.database : TestCaseId, TestCaseInfo;
    import dextool.set;

    auto profile = Profile(ReportSection.tc_min_set);

    alias TcIdInfo = Tuple!(TestCase, "tc", TestCaseId, "id", TestCaseInfo, "info");

    MinimalTestSet rval;

    Set!MutationId killedMutants;

    // start by picking test cases that have the fewest kills.
    foreach (const val; db.getDetectedTestCases
            .map!(a => tuple(a, db.getTestCaseId(a)))
            .filter!(a => !a[1].isNull)
            .map!(a => TcIdInfo(a[0], a[1], db.getTestCaseInfo(a[0], kinds)))
            .filter!(a => a.info.killedMutants != 0)
            .array
            .sort!((a, b) => a.info.killedMutants < b.info.killedMutants)) {
        rval.testCaseTime[val.tc.name] = val.info;

        const killed = killedMutants.length;
        foreach (const id; db.getTestCaseMutantKills(val.id, kinds)) {
            killedMutants.add(id);
        }

        if (killedMutants.length > killed)
            rval.minimalSet ~= val.tc;
        else
            rval.redundant ~= val.tc;
    }

    rval.total = rval.minimalSet.length + rval.redundant.length;

    return rval;
}

struct TestCaseUniqueness {
    MutationId[][TestCase] uniqueKills;

    // test cases that have no unique kills. These are candidates for being
    // refactored/removed.
    TestCase[] noUniqueKills;
}

/// Returns: a report of the mutants that a test case is the only one that kills.
TestCaseUniqueness reportTestCaseUniqueness(ref Database db, const Mutation.Kind[] kinds) {
    import dextool.plugin.mutate.backend.database.type : TestCaseId;
    import dextool.set;

    auto profile = Profile(ReportSection.tc_unique);

    /// any time a mutant is killed by more than one test case it is removed.
    TestCaseId[MutationId] killedBy;
    Set!MutationId blacklist;

    foreach (tc_id; db.getTestCasesWithAtLeastOneKill(kinds)) {
        auto muts = db.getTestCaseMutantKills(tc_id, kinds);
        foreach (m; muts.filter!(a => !blacklist.contains(a))) {
            if (m in killedBy) {
                killedBy.remove(m);
                blacklist.add(m);
            } else {
                killedBy[m] = tc_id;
            }
        }
    }

    // use a cache to reduce the database access
    TestCase[TestCaseId] idToTc;
    TestCase getTestCase(TestCaseId id) @trusted {
        return idToTc.require(id, spinSql!(() { return db.getTestCase(id).get; }));
    }

    typeof(return) rval;
    Set!TestCaseId uniqueTc;
    foreach (kv; killedBy.byKeyValue) {
        rval.uniqueKills[getTestCase(kv.value)] ~= kv.key;
        uniqueTc.add(kv.value);
    }
    foreach (tc_id; db.getDetectedTestCaseIds.filter!(a => !uniqueTc.contains(a))) {
        rval.noUniqueKills ~= getTestCase(tc_id);
    }

    return rval;
}

private:

/** Measure how long a report takes to generate and print it as trace data.
 *
 * This is an example from clang-tidy for how it could be reported to the user.
 * For now it is *just* reported as it is running.
 *
 * ===-------------------------------------------------------------------------===
 *                           clang-tidy checks profiling
 * ===-------------------------------------------------------------------------===
 *   Total Execution Time: 0.0021 seconds (0.0021 wall clock)
 *
 *    ---User Time---   --System Time--   --User+System--   ---Wall Time---  --- Name ---
 *    0.0000 (  0.1%)   0.0000 (  0.0%)   0.0000 (  0.0%)   0.0000 (  0.1%)  readability-misplaced-array-index
 *    0.0000 (  0.2%)   0.0000 (  0.0%)   0.0000 (  0.1%)   0.0000 (  0.1%)  abseil-duration-division
 *    0.0012 (100.0%)   0.0009 (100.0%)   0.0021 (100.0%)   0.0021 (100.0%)  Total
 */
struct Profile {
    import std.datetime.stopwatch : StopWatch;

    ReportSection kind;
    StopWatch sw;

    this(ReportSection kind) @safe nothrow @nogc {
        this.kind = kind;
        sw.start;
    }

    ~this() @safe nothrow {
        try {
            sw.stop;
            logger.tracef("profiling:%s wall time:%s", kind, sw.peek);
        } catch (Exception e) {
        }
    }
}
