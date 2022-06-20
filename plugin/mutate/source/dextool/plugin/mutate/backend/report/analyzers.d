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
import std.algorithm : sum, map, sort, filter, count, cmp, joiner, among;
import std.array : array, appender, empty;
import std.conv : to;
import std.datetime : SysTime, Duration;
import std.exception : collectException;
import std.format : format;
import std.range : take, retro, only;
import std.typecons : Flag, Yes, No, Tuple, Nullable, tuple;

import my.named_type;
import my.optional;
import my.set;

import dextool.plugin.mutate.backend.database : Database, spinSql, MutationId,
    MarkedMutant, TestCaseId, MutationStatusId;
import dextool.plugin.mutate.backend.diff_parser : Diff;
import dextool.plugin.mutate.backend.generate_mutant : MakeMutationTextResult,
    makeMutationText, makeMutation;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.report.utility : window, windowSize,
    statusToString, kindToString;
import dextool.plugin.mutate.backend.type : Mutation, Offset, TestCase, TestGroup;
import dextool.plugin.mutate.backend.utility : Profile;
import dextool.plugin.mutate.type : ReportKillSortOrder, ReportSection;
import dextool.type;

static import dextool.plugin.mutate.backend.database.type;

public import dextool.plugin.mutate.backend.report.utility : Table;
public import dextool.plugin.mutate.backend.type : MutantTimeProfile;

version (unittest) {
    import unit_threaded.assertions;
}

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

/** Test case score based on how many mutants they killed.
 */
struct TestCaseStat {
    import dextool.plugin.mutate.backend.database.type : TestCaseInfo;

    struct Info {
        double ratio = 0.0;
        TestCase tc;
        TestCaseInfo info;
        alias info this;
    }

    Info[TestCase] testCases;

    /// Returns: the test cases sorted from most kills to least kills.
    auto toSortedRange() {
        static bool cmp(T)(ref T a, ref T b) {
            if (a.killedMutants > b.killedMutants)
                return true;
            else if (a.killedMutants < b.killedMutants)
                return false;
            else if (a.tc.name > b.tc.name)
                return true;
            else if (a.tc.name < b.tc.name)
                return false;
            return false;
        }

        return testCases.byValue.array.sort!cmp;
    }
}

/** Update the table with the score of test cases and how many mutants they killed.
 *
 * Params:
 *  take_ = how many from the top should be moved to the table
 *  sort_order = ctrl if the top or bottom of the test cases should be reported
 *  tbl = table to write the data to
 */
void toTable(ref TestCaseStat st, const long take_,
        const ReportKillSortOrder sort_order, ref Table!3 tbl) @safe nothrow {
    auto takeOrder(RangeT)(RangeT range) {
        final switch (sort_order) {
        case ReportKillSortOrder.top:
            return range.take(take_).array;
        case ReportKillSortOrder.bottom:
            return range.retro.take(take_).array;
        }
    }

    foreach (v; takeOrder(st.toSortedRange)) {
        try {
            typeof(tbl).Row r = [
                (100.0 * v.ratio).to!string, v.info.killedMutants.to!string,
                v.tc.name
            ];
            tbl.put(r);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }
}

/** Extract the number of source code mutants that a test case has killed and
 * how much the kills contributed to the total.
 */
TestCaseStat reportTestCaseStats(ref Database db, const Mutation.Kind[] kinds) @safe nothrow {
    import dextool.plugin.mutate.backend.database.type : TestCaseInfo;

    auto profile = Profile(ReportSection.tc_stat);

    const total = spinSql!(() { return db.mutantApi.totalSrcMutants(kinds).count; });
    // nothing to do. this also ensure that we do not divide by zero.
    if (total == 0)
        return TestCaseStat.init;

    alias TcInfo = Tuple!(TestCase, "tc", TestCaseInfo, "info");
    alias TcInfo2 = Tuple!(TestCase, "tc", Nullable!TestCaseInfo, "info");
    TestCaseStat rval;

    foreach (v; spinSql!(() { return db.testCaseApi.getDetectedTestCases; }).map!(
            a => TcInfo2(a, spinSql!(() {
                return db.testCaseApi.getTestCaseInfo(a, kinds);
            })))
            .filter!(a => !a.info.isNull)
            .map!(a => TcInfo(a.tc, a.info.get))) {
        try {
            const ratio = cast(double) v.info.killedMutants / cast(double) total;
            rval.testCases[v.tc] = TestCaseStat.Info(ratio, v.tc, v.info);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    return rval;
}

/** The result of analysing the test cases to see how similare they are to each
 * other.
 */
class TestCaseSimilarityAnalyse {
    import dextool.plugin.mutate.backend.type : TestCase;

    static struct Similarity {
        TestCaseId testCase;
        double similarity = 0.0;
        /// Mutants that are similare between `testCase` and the parent.
        MutationStatusId[] intersection;
        /// Unique mutants that are NOT verified by `testCase`.
        MutationStatusId[] difference;
    }

    Similarity[][TestCaseId] similarities;
}

/// The result of the similarity analyse
private struct Similarity {
    /// The quota |A intersect B| / |A|. Thus it is how similare A is to B. If
    /// B ever fully encloses A then the score is 1.0.
    double similarity = 0.0;
    MutationStatusId[] intersection;
    MutationStatusId[] difference;
}

// The set similairty measures how much of lhs is in rhs. This is a
// directional metric.
private Similarity setSimilarity(MutationStatusId[] lhs_, MutationStatusId[] rhs_) {
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
    import dextool.plugin.mutate.backend.database.type : TestCaseInfo;

    auto profile = Profile(ReportSection.tc_similarity);

    // TODO: reduce the code duplication of the caches.
    // The DB lookups must be cached or otherwise the algorithm becomes too
    // slow for practical use.

    MutationStatusId[][TestCaseId] kill_cache2;
    MutationStatusId[] getKills(TestCaseId id) @trusted {
        return kill_cache2.require(id, spinSql!(() {
                return db.testCaseApi.testCaseKilledSrcMutants(kinds, id);
            }));
    }

    alias TcKills = Tuple!(TestCaseId, "id", MutationStatusId[], "kills");

    const test_cases = spinSql!(() {
        return db.testCaseApi.getDetectedTestCaseIds;
    });

    auto rval = new typeof(return);

    foreach (tc_kill; test_cases.map!(a => TcKills(a, getKills(a)))
            .filter!(a => a.kills.length != 0)) {
        auto app = appender!(TestCaseSimilarityAnalyse.Similarity[])();
        foreach (tc; test_cases.filter!(a => a != tc_kill.id)
                .map!(a => TcKills(a, getKills(a)))
                .filter!(a => a.kills.length != 0)) {
            auto distance = setSimilarity(tc_kill.kills, tc.kills);
            if (distance.similarity > 0)
                app.put(TestCaseSimilarityAnalyse.Similarity(tc.id,
                        distance.similarity, distance.intersection, distance.difference));
        }
        if (app.data.length != 0) {
            () @trusted {
                rval.similarities[tc_kill.id] = heapify!((a,
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
    double ratio = 0.0;
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
    r.total = db.testCaseApi.getNumOfTestCases;
    r.testCases = db.testCaseApi.getTestCasesWithZeroKills;
    if (r.total > 0)
        r.ratio = cast(double) r.numDeadTC / cast(double) r.total;
    return r;
}

/// Only the mutation score thus a subset of all statistics.
struct MutationScore {
    import core.time : Duration;

    long alive;
    long killed;
    long timeout;
    long total;
    long noCoverage;
    long equivalent;
    long skipped;
    long memOverload;
    MutantTimeProfile totalTime;

    // Nr of mutants that are alive but tagged with nomut.
    long aliveNoMut;
    string filePath;

    double score() @safe pure nothrow const @nogc {
        if ((total - aliveNoMut) > 0) {
            return cast(double)(killed + timeout + memOverload) / cast(double)(total - aliveNoMut);
        }
        return 0.0;
    }
}

MutationScore reportScore(ref Database db, const Mutation.Kind[] kinds, string file = null) @safe nothrow {
    auto profile = Profile("reportScore");

    typeof(return) rval;
    rval.alive = spinSql!(() => db.mutantApi.aliveSrcMutants(kinds, file)).count;
    rval.killed = spinSql!(() => db.mutantApi.killedSrcMutants(kinds, file)).count;
    rval.timeout = spinSql!(() => db.mutantApi.timeoutSrcMutants(kinds, file)).count;
    rval.aliveNoMut = spinSql!(() => db.mutantApi.aliveNoMutSrcMutants(kinds, file)).count;
    rval.noCoverage = spinSql!(() => db.mutantApi.noCovSrcMutants(kinds, file)).count;
    rval.equivalent = spinSql!(() => db.mutantApi.equivalentMutants(kinds, file)).count;
    rval.skipped = spinSql!(() => db.mutantApi.skippedMutants(kinds, file)).count;
    rval.memOverload = spinSql!(() => db.mutantApi.memOverloadMutants(kinds, file)).count;

    const total = spinSql!(() => db.mutantApi.totalSrcMutants(kinds, file));
    rval.totalTime = total.time;
    rval.total = total.count;

    return rval;
}

MutationScore[] reportScores(ref Database db, const Mutation.Kind[] kinds, string[] files) @safe nothrow {
    auto profile = Profile("reportScores");
    auto app = appender!(MutationScore[]);

    foreach(file; files){
      MutationScore result;
      result.alive = spinSql!(() => db.mutantApi.aliveSrcMutants(kinds, file)).count;
      result.killed = spinSql!(() => db.mutantApi.killedSrcMutants(kinds, file)).count;
      result.timeout = spinSql!(() => db.mutantApi.timeoutSrcMutants(kinds, file)).count;
      result.aliveNoMut = spinSql!(() => db.mutantApi.aliveNoMutSrcMutants(kinds, file)).count;
      result.noCoverage = spinSql!(() => db.mutantApi.noCovSrcMutants(kinds, file)).count;
      result.equivalent = spinSql!(() => db.mutantApi.equivalentMutants(kinds, file)).count;
      result.skipped = spinSql!(() => db.mutantApi.skippedMutants(kinds, file)).count;
      result.memOverload = spinSql!(() => db.mutantApi.memOverloadMutants(kinds, file)).count;

      const total = spinSql!(() => db.mutantApi.totalSrcMutants(kinds, file));
      result.totalTime = total.time;
      result.total = total.count;
      result.filePath = file;

      app.put(result);
    }

    return app.data;
}


/// Statistics for a group of mutants.
struct MutationStat {
    import core.time : Duration;
    import std.range : isOutputRange;

    long untested;
    long killedByCompiler;
    long worklist;

    long alive() @safe pure nothrow const @nogc {
        return scoreData.alive;
    }

    long noCoverage() @safe pure nothrow const @nogc {
        return scoreData.noCoverage;
    }

    /// Nr of mutants that are alive but tagged with nomut.
    long aliveNoMut() @safe pure nothrow const @nogc {
        return scoreData.aliveNoMut;
    }

    long killed() @safe pure nothrow const @nogc {
        return scoreData.killed;
    }

    long timeout() @safe pure nothrow const @nogc {
        return scoreData.timeout;
    }

    long equivalent() @safe pure nothrow const @nogc {
        return scoreData.equivalent;
    }

    long skipped() @safe pure nothrow const @nogc {
        return scoreData.skipped;
    }

    long memOverload() @safe pure nothrow const @nogc {
        return scoreData.memOverload;
    }

    long total() @safe pure nothrow const @nogc {
        return scoreData.total;
    }

    MutantTimeProfile totalTime() @safe pure nothrow const @nogc {
        return scoreData.totalTime;
    }

    MutationScore scoreData;
    MutantTimeProfile killedByCompilerTime;
    Duration predictedDone;

    /// Adjust the score with the alive mutants that are suppressed.
    double score() @safe pure nothrow const @nogc {
        return scoreData.score;
    }

    /// Suppressed mutants of the total mutants.
    double suppressedOfTotal() @safe pure nothrow const @nogc {
        if (total > 0) {
            return (cast(double)(aliveNoMut) / cast(double) total);
        }
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

        immutable align_ = 19;

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
        if (skipped > 0)
            formattedWrite(w, "%-*s %s\n", align_, "Skipped:", skipped);
        if (equivalent > 0)
            formattedWrite(w, "%-*s %s\n", align_, "Equivalent:", equivalent);
        formattedWrite(w, "%-*s %s\n", align_, "Timeout:", timeout);
        formattedWrite(w, "%-*s %s\n", align_, "Killed by compiler:", killedByCompiler);
        if (worklist > 0) {
            formattedWrite(w, "%-*s %s\n", align_, "Worklist:", worklist);
        }

        if (aliveNoMut > 0) {
            formattedWrite(w, "%-*s %s (%.3s)\n", align_,
                    "Suppressed (nomut):", aliveNoMut, suppressedOfTotal);
        }
    }
}

MutationStat reportStatistics(ref Database db, const Mutation.Kind[] kinds, string file = null) @safe nothrow {
    import core.time : dur;
    import dextool.plugin.mutate.backend.utility;

    auto profile = Profile(ReportSection.summary);

    const untested = spinSql!(() => db.mutantApi.unknownSrcMutants(kinds, file));
    const worklist = spinSql!(() => db.worklistApi.getCount);
    const killedByCompiler = spinSql!(() => db.mutantApi.killedByCompilerSrcMutants(kinds, file));

    MutationStat st;
    st.scoreData = reportScore(db, kinds, file);
    st.untested = untested.count;
    st.killedByCompiler = killedByCompiler.count;
    st.worklist = worklist;

    st.predictedDone = () {
        auto avg = calcAvgPerMutant(db, kinds);
        return (st.worklist * avg.total!"msecs").dur!"msecs";
    }();
    st.killedByCompilerTime = killedByCompiler.time;

    return st;
}

struct MarkedMutantsStat {
    Table!6 tbl;
}

MarkedMutantsStat reportMarkedMutants(ref Database db, const Mutation.Kind[] kinds,
        string file = null) @safe {
    MarkedMutantsStat st;
    st.tbl.heading = [
        "File", "Line", "Column", "Mutation", "Status", "Rationale"
    ];

    foreach (m; db.markMutantApi.getMarkedMutants()) {
        typeof(st.tbl).Row r = [
            m.path, m.sloc.line.to!string, m.sloc.column.to!string,
            m.mutText, statusToString(m.toStatus), m.rationale.get
        ];
        st.tbl.put(r);
    }
    return st;
}

struct TestCaseOverlapStat {
    import std.format : formattedWrite;
    import std.range : put;
    import my.hash;

    long overlap;
    long total;
    double ratio = 0.0;

    // map between test cases and the mutants they have killed.
    TestCaseId[][Murmur3] tc_mut;
    // map between mutation IDs and the test cases that killed them.
    long[][Murmur3] mutid_mut;
    string[TestCaseId] name_tc;

    string sumToString() @safe const {
        return format("%s/%s = %s test cases", overlap, total, ratio);
    }

    void sumToString(Writer)(ref Writer w) @trusted const {
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
                    () @trusted {
                        formattedWrite(w, "%s %s\n", name, mutid_mut[tcs.key].length);
                    }();
                    first = false;
                } else {
                    () @trusted { formattedWrite(w, "%s\n", name); }();
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
    import my.hash;

    auto profile = Profile(ReportSection.tc_full_overlap);

    TestCaseOverlapStat st;
    st.total = db.testCaseApi.getNumOfTestCases;

    foreach (tc_id; db.testCaseApi.getTestCasesWithAtLeastOneKill(kinds)) {
        auto muts = db.testCaseApi.getTestCaseMutantKills(tc_id, kinds)
            .sort.map!(a => cast(long) a).array;
        auto m3 = makeMurmur3(cast(ubyte[]) muts);
        if (auto v = m3 in st.tc_mut)
            (*v) ~= tc_id;
        else {
            st.tc_mut[m3] = [tc_id];
            st.mutid_mut[m3] = muts;
        }
        st.name_tc[tc_id] = db.testCaseApi.getTestCaseName(tc_id);
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
        double similarity = 0.0;
        /// Mutants that are similare between `testCase` and the parent.
        MutationStatusId[] intersection;
        /// Unique mutants that are NOT verified by `testCase`.
        MutationStatusId[] difference;
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
    auto profile = Profile(ReportSection.tc_groups_similarity);

    alias TgKills = Tuple!(TestGroupSimilarity.TestGroup, "testGroup",
            MutationStatusId[], "kills");

    const test_cases = spinSql!(() {
        return db.testCaseApi.getDetectedTestCaseIds;
    }).map!(a => Tuple!(TestCaseId, "id", TestCase, "tc")(a, spinSql!(() {
                return db.testCaseApi.getTestCase(a).get;
            }))).array;

    MutationStatusId[] gatherKilledMutants(const(TestGroup) tg) {
        auto kills = appender!(MutationStatusId[])();
        foreach (tc; test_cases.filter!(a => a.tc.isTestCaseInTestGroup(tg.re))) {
            kills.put(spinSql!(() {
                    return db.testCaseApi.testCaseKilledSrcMutants(kinds, tc.id);
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
    import dextool.plugin.mutate.backend.database : FileId, MutantInfo;

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
    foreach (tc; db.testCaseApi.getDetectedTestCases) {
        if (tc.isTestCaseInTestGroup(test_g.re))
            r.testCases ~= tc;
    }

    // collect mutation statistics for each test case group
    foreach (const tc; r.testCases) {
        foreach (const id; db.testCaseApi.testCaseMutationPointAliveSrcMutants(kinds, tc))
            tc_stat.alive.add(id);
        foreach (const id; db.testCaseApi.testCaseMutationPointKilledSrcMutants(kinds, tc))
            tc_stat.killed.add(id);
        foreach (const id; db.testCaseApi.testCaseMutationPointTimeoutSrcMutants(kinds, tc))
            tc_stat.timeout.add(id);
        foreach (const id; db.testCaseApi.testCaseMutationPointTotalSrcMutants(kinds, tc))
            tc_stat.total.add(id);
        foreach (const id; db.testCaseApi.testCaseKilledSrcMutants(kinds, tc))
            tc_stat.tcKilled.add(id);
    }

    // update the mutation stat for the test group
    r.stats.scoreData.alive = tc_stat.alive.length;
    r.stats.scoreData.killed = tc_stat.killed.length;
    r.stats.scoreData.timeout = tc_stat.timeout.length;
    r.stats.scoreData.total = tc_stat.total.length;

    // associate mutants with their file
    foreach (const m; db.mutantApi.getMutantsInfo(kinds, tc_stat.tcKilled.toArray)) {
        auto fid = db.getFileId(m.id);
        r.killed[fid.get] ~= m;

        if (fid.get !in r.files) {
            r.files[fid.get] = Path.init;
            r.files[fid.get] = db.getFile(fid.get).get;
        }
    }

    foreach (const m; db.mutantApi.getMutantsInfo(kinds, tc_stat.alive.toArray)) {
        auto fid = db.getFileId(m.id);
        r.alive[fid.get] ~= m;

        if (fid.get !in r.files) {
            r.files[fid.get] = Path.init;
            r.files[fid.get] = db.getFile(fid.get).get;
        }
    }

    return r;
}

/// High interest mutants.
class MutantSample {
    import dextool.plugin.mutate.backend.database : FileId, MutantInfo,
        MutationStatus, MutationEntry, MutationStatusTime;

    MutationEntry[MutationStatusId] mutants;

    /// The mutant that had its status updated the furthest back in time.
    //MutationStatusTime[] oldest;

    /// The mutant that has survived the longest in the system.
    MutationStatus[] highestPrio;

    /// The latest mutants that where added and survived.
    MutationStatusTime[] latest;
}

/// Returns: samples of mutants that are of high interest to the user.
MutantSample reportSelectedAliveMutants(ref Database db, const(Mutation.Kind)[] kinds,
        long historyNr) {
    auto profile = Profile(ReportSection.mut_recommend_kill);

    auto rval = new typeof(return);

    rval.highestPrio = db.mutantApi.getHighestPrioMutant(kinds, Mutation.Status.alive, historyNr);
    foreach (const mutst; rval.highestPrio) {
        auto ids = db.mutantApi.getMutationIds(kinds, [mutst.statusId]);
        if (ids.length != 0)
            rval.mutants[mutst.statusId] = db.mutantApi.getMutation(ids[0]).get;
    }

    //rval.oldest = db.mutantApi.getOldestMutants(kinds, historyNr, [EnumMembers!(Mutation.Status)].filter!(a => a != Mutation.Status.noCoverage).array);
    //foreach (const mutst; rval.oldest) {
    //    auto ids = db.mutantApi.getMutationIds(kinds, [mutst.id]);
    //    if (ids.length != 0)
    //        rval.mutants[mutst.id] = db.mutantApi.getMutation(ids[0]).get;
    //}

    return rval;
}

class DiffReport {
    import dextool.plugin.mutate.backend.database : FileId, MutantInfo;
    import dextool.plugin.mutate.backend.diff_parser : Diff;

    /// The mutation score.
    double score = 0.0;

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
            put(w, file.value.toString);
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
    import dextool.plugin.mutate.backend.type : SourceLoc;

    auto profile = Profile(ReportSection.diff);

    auto rval = new DiffReport;

    Set!MutationStatusId total;
    Set!MutationId alive;
    Set!MutationId killed;

    foreach (kv; diff.toRange(workdir)) {
        auto fid = db.getFileId(kv.key);
        if (fid.isNull) {
            logger.warning("This file in the diff has not been tested thus skipping it: ", kv.key);
            continue;
        }

        bool hasMutants;
        foreach (id; kv.value
                .toRange
                .map!(line => spinSql!(() => db.mutantApi.getMutationsOnLine(kinds,
                    fid.get, SourceLoc(line))))
                .joiner
                .filter!(a => a !in total)) {
            hasMutants = true;
            total.add(id);

            const info = db.mutantApi.getMutantsInfo(kinds, [id])[0];
            if (info.status == Mutation.Status.alive) {
                rval.alive[fid.get] ~= info;
                alive.add(info.id);
            } else if (info.status.among(Mutation.Status.killed, Mutation.Status.timeout)) {
                rval.killed[fid.get] ~= info;
                killed.add(info.id);
            }
        }

        if (hasMutants) {
            rval.files[fid.get] = kv.key;
            rval.rawDiff[fid.get] = diff.rawDiff[kv.key];
        } else {
            logger.info("This file in the diff has no mutants on changed lines: ", kv.key);
        }
    }

    Set!TestCase test_cases;
    foreach (tc; killed.toRange.map!(a => db.testCaseApi.getTestCases(a)).joiner) {
        test_cases.add(tc);
    }

    rval.testCases = test_cases.toArray.sort.array;

    if (total.length == 0) {
        rval.score = 1.0;
    } else {
        // TODO: use total to compute e.g. a standard deviation or some other
        // useful statistical metric to convey a "confidence" of the value.
        rval.score = cast(double) killed.length / cast(double)(killed.length + alive.length);
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
    import dextool.plugin.mutate.backend.database : TestCaseInfo;

    auto profile = Profile(ReportSection.tc_min_set);

    alias TcIdInfo = Tuple!(TestCase, "tc", TestCaseId, "id", TestCaseInfo, "info");

    MinimalTestSet rval;

    Set!MutationId killedMutants;

    // start by picking test cases that have the fewest kills.
    foreach (const val; db.testCaseApi
            .getDetectedTestCases
            .map!(a => tuple(a, db.testCaseApi.getTestCaseId(a)))
            .filter!(a => !a[1].isNull)
            .map!(a => TcIdInfo(a[0], a[1].get, db.testCaseApi.getTestCaseInfo(a[0], kinds).get))
            .filter!(a => a.info.killedMutants != 0)
            .array
            .sort!((a, b) => a.info.killedMutants < b.info.killedMutants)) {
        rval.testCaseTime[val.tc.name] = val.info;

        const killed = killedMutants.length;
        foreach (const id; db.testCaseApi.getTestCaseMutantKills(val.id, kinds)) {
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
    MutationStatusId[][TestCaseId] uniqueKills;

    // test cases that have no unique kills. These are candidates for being
    // refactored/removed.
    Set!TestCaseId noUniqueKills;
}

/// Returns: a report of the mutants that a test case is the only one that kills.
TestCaseUniqueness reportTestCaseUniqueness(ref Database db, const Mutation.Kind[] kinds) {
    import dextool.plugin.mutate.backend.database.type : MutationStatusId;

    auto profile = Profile(ReportSection.tc_unique);

    // any time a mutant is killed by more than one test case it is removed.
    TestCaseId[MutationStatusId] killedBy;
    // killed by multiple test cases
    Set!MutationStatusId multiKill;

    foreach (tc_id; db.testCaseApi.getTestCasesWithAtLeastOneKill(kinds)) {
        auto muts = db.testCaseApi.testCaseKilledSrcMutants(kinds, tc_id);
        foreach (m; muts.filter!(a => a !in multiKill)) {
            if (m in killedBy) {
                killedBy.remove(m);
                multiKill.add(m);
            } else {
                killedBy[m] = tc_id;
            }
        }
    }

    typeof(return) rval;
    Set!TestCaseId uniqueTc;
    foreach (kv; killedBy.byKeyValue) {
        rval.uniqueKills[kv.value] ~= kv.key;
        uniqueTc.add(kv.value);
    }
    foreach (tc_id; db.testCaseApi.getDetectedTestCaseIds.filter!(a => !uniqueTc.contains(a)))
        rval.noUniqueKills.add(tc_id);

    return rval;
}

/// Estimate the mutation score.
struct EstimateMutationScore {
    import my.signal_theory.kalman : KalmanFilter;

    private KalmanFilter kf;

    void update(const double a) {
        kf.updateEstimate(a);
    }

    /// The estimated mutation score.
    NamedType!(double, Tag!"EstimatedMutationScore", 0.0, TagStringable) value() @safe pure nothrow const @nogc {
        return typeof(return)(kf.currentEstimate);
    }

    /// The error in the estimate. The unit is the same as `estimate`.
    NamedType!(double, Tag!"MutationScoreError", 0.0, TagStringable) error() @safe pure nothrow const @nogc {
        return typeof(return)(kf.estimateError);
    }
}

/// Estimate the mutation score.
struct EstimateScore {
    import my.signal_theory.kalman : KalmanFilter;

    // 0.5 because then it starts in the middle of range possible values.
    // 0.01 such that the trend is "slowly" changing over the last 100 mutants.
    // 0.001 is to "insensitive" for an on the fly analysis so it mostly just
    //  end up being the current mutation score.
    private EstimateMutationScore estimate = EstimateMutationScore(KalmanFilter(0.5, 0.5, 0.01));

    /// Update the estimate with the status of a mutant.
    void update(const Mutation.Status s) {
        import std.algorithm : among;

        if (s.among(Mutation.Status.unknown, Mutation.Status.killedByCompiler)) {
            return;
        }

        const v = () {
            final switch (s) with (Mutation.Status) {
            case unknown:
                goto case;
            case killedByCompiler:
                return 0.5; // shouldnt happen but...
            case skipped:
                goto case;
            case noCoverage:
                goto case;
            case alive:
                return 0.0;
            case killed:
                goto case;
            case timeout:
                goto case;
            case memOverload:
                goto case;
            case equivalent:
                return 1.0;
            }
        }();

        estimate.update(v);
    }

    /// The estimated mutation score.
    auto value() @safe pure nothrow const @nogc {
        return estimate.value;
    }

    /// The error in the estimate. The unit is the same as `estimate`.
    auto error() @safe pure nothrow const @nogc {
        return estimate.error;
    }
}

/// Estimated trend based on the latest code changes.
struct ScoreTrendByCodeChange {
    static struct Point {
        SysTime timeStamp;

        /// The estimated mutation score.
        NamedType!(double, Tag!"EstimatedMutationScore", 0.0, TagStringable) value;

        /// The error in the estimate. The unit is the same as `estimate`.
        NamedType!(double, Tag!"MutationScoreError", 0.0, TagStringable) error;
    }

    Point[] sample;

    NamedType!(double, Tag!"EstimatedMutationScore", 0.0, TagStringable) value() @safe pure nothrow const @nogc {
        if (sample.empty)
            return typeof(return).init;
        return sample[$ - 1].value;
    }

    NamedType!(double, Tag!"MutationScoreError", 0.0, TagStringable) error() @safe pure nothrow const @nogc {
        if (sample.empty)
            return typeof(return).init;
        return sample[$ - 1].error;
    }
}

/** Estimate the mutation score by running a kalman filter over the mutants in
 * the order they have been tested. It gives a rough estimate of where the test
 * suites quality is going over time.
 *
 */
ScoreTrendByCodeChange reportTrendByCodeChange(ref Database db, const Mutation.Kind[] kinds) @trusted nothrow {
    auto app = appender!(ScoreTrendByCodeChange.Point[])();
    EstimateScore estimate;

    try {
        SysTime lastAdded;
        SysTime last;
        bool first = true;
        void fn(const Mutation.Status s, const SysTime added) {
            estimate.update(s);
            debug logger.trace(estimate.estimate.kf).collectException;

            if (first)
                lastAdded = added;

            if (added != lastAdded) {
                app.put(ScoreTrendByCodeChange.Point(added, estimate.value, estimate.error));
                lastAdded = added;
            }

            last = added;
            first = false;
        }

        db.iterateMutantStatus(kinds, &fn);
        app.put(ScoreTrendByCodeChange.Point(last, estimate.value, estimate.error));
    } catch (Exception e) {
        logger.warning(e.msg).collectException;
    }
    return ScoreTrendByCodeChange(app.data);
}

/** History of how the mutation score have evolved over time.
 *
 * The history is ordered in ascending by date. Each day is the average of the
 * recorded mutation score.
 */
struct MutationScoreHistory {
    import dextool.plugin.mutate.backend.database.type : MutationScore;

    enum Trend {
        undecided,
        negative,
        positive
    }

    static struct Estimate {
        SysTime x;
        double avg = 0;
        SysTime predX;
        double predScore = 0;
        Trend trend;
    }

    /// only one score for each date.
    MutationScore[] data;
    Estimate estimate;

    this(MutationScore[] data) {
        import std.algorithm : sum, map, min;

        this.data = data;
        if (data.length < 6)
            return;

        const values = data[$ - 5 .. $];
        {
            const avg = sum(values.map!(a => a.score.get)) / 5.0;
            const xDiff = values[$ - 1].timeStamp - values[0].timeStamp;
            const dy = (values[$ - 1].score.get - avg) / (xDiff.total!"days" / 2.0);

            estimate.x = values[0].timeStamp + xDiff / 2;
            estimate.avg = avg;
            estimate.predX = values[$ - 1].timeStamp + xDiff / 2;
            estimate.predScore = min(1.0, dy * xDiff.total!"days" / 2.0 + values[$ - 1].score.get);
        }

        {
            // small changes / fluctuations are ignored
            immutable limit = 0.001;
            const diff = estimate.predScore - values[$ - 1].score.get;
            if (diff < -limit)
                estimate.trend = Trend.negative;
            else if (diff > limit)
                estimate.trend = Trend.positive;
        }
    }

    const(MutationScoreHistory) rollingAvg() @safe const {
        immutable avgDays = 7;
        if (data.length < avgDays)
            return this;

        auto app = appender!(MutationScore[])();
        foreach (i; 0 .. data.length - avgDays)
            app.put(MutationScore(data[i + avgDays].timeStamp,
                    typeof(MutationScore.score)(data[i .. i + avgDays].map!(a => a.score.get)
                    .sum / cast(double) avgDays)));
        return MutationScoreHistory(app.data);
    }
}

MutationScoreHistory reportMutationScoreHistory(ref Database db) @safe {
    return reportMutationScoreHistory(db.getMutationScoreHistory);
}

private MutationScoreHistory reportMutationScoreHistory(
        dextool.plugin.mutate.backend.database.type.MutationScore[] data) {
    import std.datetime : DateTime, Date, SysTime;
    import dextool.plugin.mutate.backend.database.type : MutationScore;

    auto pretty = appender!(MutationScore[])();

    if (data.length < 2) {
        return MutationScoreHistory(data);
    }

    auto last = (cast(DateTime) data[0].timeStamp).date;
    double acc = data[0].score.get;
    double nr = 1;
    foreach (a; data[1 .. $]) {
        auto curr = (cast(DateTime) a.timeStamp).date;
        if (curr == last) {
            acc += a.score.get;
            nr++;
        } else {
            pretty.put(MutationScore(SysTime(last), typeof(MutationScore.score)(acc / nr)));
            last = curr;
            acc = a.score.get;
            nr = 1;
        }
    }
    pretty.put(MutationScore(SysTime(last), typeof(MutationScore.score)(acc / nr)));

    return MutationScoreHistory(pretty.data);
}

@("shall calculate the mean of the mutation scores")
unittest {
    import core.time : days;
    import std.datetime : DateTime;
    import dextool.plugin.mutate.backend.database.type : MutationScore;

    auto data = appender!(MutationScore[])();
    auto d = DateTime(2000, 6, 1, 10, 30, 0);

    data.put(MutationScore(SysTime(d), typeof(MutationScore.score)(10.0)));
    data.put(MutationScore(SysTime(d), typeof(MutationScore.score)(5.0)));
    data.put(MutationScore(SysTime(d + 1.days), typeof(MutationScore.score)(5.0)));

    auto res = reportMutationScoreHistory(data.data);

    res.data[0].score.get.shouldEqual(7.5);
    res.data[1].score.get.shouldEqual(5.0);
}

/** Sync status is how old the information about mutants and their status is
 * compared to when the tests or source code where last changed.
 */
struct SyncStatus {
    import dextool.plugin.mutate.backend.database : MutationStatusTime;

    SysTime test;
    SysTime code;
    SysTime coverage;
    MutationStatusTime[] mutants;
}

SyncStatus reportSyncStatus(ref Database db, const(Mutation.Kind)[] kinds, const long nrMutants) {
    import std.datetime : Clock;
    import std.traits : EnumMembers;
    import dextool.plugin.mutate.backend.database : TestFile, TestFileChecksum, TestFilePath;

    typeof(return) rval;
    rval.test = spinSql!(() => db.testFileApi.getNewestTestFile)
        .orElse(TestFile(TestFilePath.init, TestFileChecksum.init, Clock.currTime)).timeStamp;
    rval.code = spinSql!(() => db.getNewestFile).orElse(Clock.currTime);
    rval.coverage = spinSql!(() => db.coverageApi.getCoverageTimeStamp).orElse(Clock.currTime);
    rval.mutants = spinSql!(() => db.mutantApi.getOldestMutants(kinds,
            nrMutants,
            [EnumMembers!(Mutation.Status)].filter!(a => a != Mutation.Status.noCoverage).array));
    return rval;
}

struct TestCaseClassifier {
    long threshold;
}

TestCaseClassifier makeTestCaseClassifier(ref Database db, const long minThreshold) {
    import std.algorithm : maxElement, max, minElement;
    import std.datetime : dur;
    import std.math : abs;
    import dextool.plugin.mutate.backend.report.kmean;

    auto profile = Profile("test case classifier");

    // the distribution is bimodal (U shaped) with one or more tops depending
    // on the architecture. The left most edge is the leaf functionality and
    // the rest of the edges are the main data flows.
    //
    // Even though the formula below assume a normal distribution and,
    // obviously, this isn't one the result is totally fine because the purpuse
    // is to classify "bad" test cases by checking if all mutants that they
    // kill are above the threshold. The threshold, as calculcated, thus
    // centers around the mean and moves further to the right the further the
    // edges are. It also, suitably, handle multiple edges because the only
    // important factor is to not get "too close" to the left most edge. That
    // would lead to false classifications.

    auto tcKills = db.mutantApi
        .getAllTestCaseKills
        .filter!"a>0"
        .map!(a => Point(cast(double) a))
        .array;
    // no use in a classifier if there are too mutants.
    if (tcKills.length < 100)
        return TestCaseClassifier(minThreshold);

    // 0.1 is good enough because it is then rounded.
    auto iter = KmeanIterator!Point(0.1);
    iter.clusters ~= Cluster!Point(0);
    // div by 2 reduces the number of iterations for a typical sample.
    iter.clusters ~= Cluster!Point(cast(double) tcKills.map!(a => a.value).maxElement / 2.0);

    iter.fit(tcKills, 1000, 10.dur!"seconds");

    TestCaseClassifier rval;
    rval.threshold = 1 + cast(long)(
            iter.clusters.map!"a.mean".minElement + abs(
            iter.clusters[0].mean - iter.clusters[1].mean) / 2.0);

    logger.tracef("calculated threshold: %s iterations:%s time:%s cluster.mean: %s",
            rval.threshold, iter.iterations, iter.time, iter.clusters.map!(a => a.mean));
    rval.threshold = max(rval.threshold, minThreshold);

    return rval;
}

struct TestCaseMetadata {
    static struct Location {
        string file;
        Optional!uint line;
    }

    string[TestCase] text;
    Location[TestCase] loc;

    /// If the user has manually marked a test case as redundant or not.
    bool[TestCase] redundant;
}

TestCaseMetadata parseTestCaseMetadata(AbsolutePath metadataPath) @trusted {
    import std.json;
    import std.file : readText;

    TestCaseMetadata rval;
    JSONValue jraw;
    try {
        jraw = parseJSON(readText(metadataPath.toString));
    } catch (Exception e) {
        logger.warning("Error reading ", metadataPath);
        logger.info(e.msg);
        return rval;
    }

    try {
        foreach (jtc; jraw.array) {
            TestCase tc;

            try {
                if (auto v = "name" in jtc) {
                    tc = TestCase(v.str);
                } else {
                    logger.warning("Missing `name` in ", jtc.toPrettyString);
                    continue;
                }

                if (auto v = "text" in jtc)
                    rval.text[tc] = v.str;
                if (auto v = "location" in jtc) {
                    TestCaseMetadata.Location loc;
                    if (auto f = "file" in *v)
                        loc.file = f.str;
                    if (auto l = "line" in *v)
                        loc.line = some(cast(uint) l.integer);
                    rval.loc[tc] = loc;
                }

                if (auto v = "redundant" in jtc)
                    rval.redundant[tc] = v.boolean;
            } catch (Exception e) {
                logger.warning("Error parsing ", jtc.toPrettyString);
                logger.warning(e.msg);
            }
        }
    } catch (Exception e) {
        logger.warning("Error parsing ", jraw.toPrettyString);
        logger.warning(e.msg);
    }

    return rval;
}

alias AverageTimePerMutant = NamedType!(Duration, Tag!"AverageTimePerMutant",
        Duration.init, TagStringable, ImplicitConvertable);

/// Based on the last 100 tested mutants.
AverageTimePerMutant calcAvgPerMutant(ref Database db, const Mutation.Kind[] kinds) nothrow {
    import core.time : dur;

    auto times = spinSql!(() => db.mutantApi.getLatestMutantTimes(kinds, 100));
    if (times.length == 0)
        return AverageTimePerMutant.init;

    const avg = (times.map!(a => a.compileTime)
            .sum
            .total!"msecs" + times.map!(a => a.testTime)
            .sum
            .total!"msecs") / times.length;
    return avg.dur!"msecs".AverageTimePerMutant;
}
