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

import dextool.plugin.mutate.backend.database : Database, spinSqlQuery, MutationId;
import dextool.plugin.mutate.backend.diff_parser : Diff;
import dextool.plugin.mutate.backend.interface_ : FilesysIO, SafeInput;
import dextool.plugin.mutate.backend.type : Mutation, Offset, TestCase, Language, TestGroup;
import dextool.plugin.mutate.type : ReportKillSortOrder;
import dextool.plugin.mutate.type : ReportLevel, ReportSection;
import dextool.type;

public import dextool.plugin.mutate.backend.generate_mutant : MakeMutationTextResult,
    makeMutationText;

// 5 because it covers all the operators and true/false
immutable windowSize = 5;

immutable invalidFile = "Dextool: Invalid UTF-8 content";

@safe:

/// Create a range from `a` that has at most maxlen+3 letters in it.
string window(T)(T a, size_t maxlen = windowSize) {
    import std.algorithm : filter, among;
    import std.conv : text;
    import std.range : take, chain;
    import std.uni : byGrapheme, byCodePoint;

    try {
        return chain(a.byGrapheme.take(maxlen)
                .byCodePoint.filter!(a => !a.among('\n')).text, a.length > maxlen ? "..." : null)
            .text;
    } catch (Exception e) {
        return "[invalid utf8]";
    }
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
            return cast(double)(killed + timeout + aliveNoMut) / cast(double) total;
        return 1.0;
    }

    /// Suppressed mutants of the total mutants.
    double suppressedOfTotal() @safe pure nothrow const @nogc {
        if (total > 0)
            return (cast(double)(aliveNoMut) / cast(double) total);
        return 0.0;
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
        formattedWrite(w, "%-*s %.3s\n", align_, "Score:", score);
        formattedWrite(w, "%-*s %s\n", align_, "Alive:", alive);
        formattedWrite(w, "%-*s %s\n", align_, "Killed:", killed);
        formattedWrite(w, "%-*s %s\n", align_, "Timeout:", timeout);
        formattedWrite(w, "%-*s %s\n", align_, "Total:", total);
        formattedWrite(w, "%-*s %s\n", align_, "Killed by compiler:", killedByCompiler);
        if (aliveNoMut != 0)
            formattedWrite(w, "%-*s %s (%.3s)\n", align_,
                    "Suppressed (nomut):", aliveNoMut, suppressedOfTotal);
    }
}

MutationStat reportStatistics(ref Database db, const Mutation.Kind[] kinds, string file = null) @safe nothrow {
    import core.time : dur;
    import std.algorithm : map, sum;
    import std.range : only;
    import dextool.plugin.mutate.backend.utility;

    const alive = spinSqlQuery!(() { return db.aliveSrcMutants(kinds, file); });
    const alive_nomut = spinSqlQuery!(() {
        return db.aliveNoMutSrcMutants(kinds, file);
    });
    const killed = spinSqlQuery!(() { return db.killedSrcMutants(kinds, file); });
    const timeout = spinSqlQuery!(() { return db.timeoutSrcMutants(kinds, file); });
    const untested = spinSqlQuery!(() { return db.unknownSrcMutants(kinds, file); });
    const killed_by_compiler = spinSqlQuery!(() {
        return db.killedByCompilerSrcMutants(kinds, file);
    });
    const total = spinSqlQuery!(() { return db.totalSrcMutants(kinds, file); });

    MutationStat st;
    st.alive = alive.count;
    st.aliveNoMut = alive_nomut.count;
    st.killed = killed.count;
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

TestGroupStat reportTestGroups(ref Database db, const(Mutation.Kind)[] kinds,
        const(TestGroup) test_g) @safe {
    import std.algorithm : filter, map;
    import std.array : appender;
    import std.typecons : tuple;
    import std.range : only;
    import dextool.plugin.mutate.backend.database : MutationStatusId;
    import dextool.set;

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
        import std.regex : matchFirst;

        auto m = matchFirst(tc.name, test_g.re);
        // the regex must match the full test case thus checking that
        // nothing is left before or after
        if (!m.empty && m.pre.length == 0 && m.post.length == 0) {
            r.testCases ~= tc;
        }
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
    foreach (const m; db.getMutantsInfo(kinds, tc_stat.tcKilled.setToList!MutationStatusId)) {
        auto fid = db.getFileId(m.id);
        r.killed[fid] ~= m;

        if (fid !in r.files) {
            r.files[fid] = Path.init;
            r.files[fid] = db.getFile(fid);
        }
    }

    foreach (const m; db.getMutantsInfo(kinds, tc_stat.alive.setToList!MutationStatusId)) {
        auto fid = db.getFileId(m.id);
        r.alive[fid] ~= m;

        if (fid !in r.files) {
            r.files[fid] = Path.init;
            r.files[fid] = db.getFile(fid);
        }
    }

    return r;
}

/// High interest mutants.
class MutantSample {
    import std.typecons : Nullable;
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
        import std.algorithm : map;
        import std.array : appender;
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
    import std.array : array;
    import std.algorithm : map, joiner, sort;
    import dextool.plugin.mutate.backend.database : MutationId;
    import dextool.plugin.mutate.backend.type : SourceLoc;
    import dextool.set;

    auto rval = new DiffReport;

    Set!MutationId killing_mutants;

    long total;
    long killed;

    foreach (kv; diff.toRange(workdir)) {
        auto fid = db.getFileId(kv.key);
        if (fid.isNull) {
            logger.warning("This file in the diff has not been tested thus skipping it: ", kv.key);
            continue;
        }

        bool has_mutants;
        foreach (line; setToRange!uint(kv.value)) {
            auto muts = db.getMutantsInfo(kinds, db.getMutationsOnLine(kinds,
                    fid, SourceLoc(line, 0)));
            foreach (m; muts) {
                has_mutants = true;
                if (m.status == Mutation.Status.alive)
                    rval.alive[fid] ~= m;
                else {
                    rval.killed[fid] ~= m;
                    killing_mutants.add(m.id);
                    ++killed;
                }
                ++total;
            }
        }

        if (has_mutants) {
            rval.files[fid] = kv.key;
            rval.rawDiff[fid] = diff.rawDiff[kv.absPath];
        } else {
            logger.info("This file in the diff has no mutants on changed lines: ", kv.key);
        }
    }

    Set!TestCase test_cases;
    foreach (tc; killing_mutants.setToRange!MutationId
            .map!(a => db.getTestCases(a))
            .joiner)
        test_cases.add(tc);

    rval.testCases = test_cases.setToList!TestCase.sort.array;

    if (total == 0) {
        rval.score = 1.0;
    } else {
        rval.score = cast(double) killed / cast(double) total;
    }

    return rval;
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
