/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

#SPC-report_for_human_plain
*/
module dextool.plugin.mutate.backend.report.plain;

import logger = std.experimental.logger;
import std.array : empty;
import std.conv : to;
import std.exception : collectException;
import std.path : buildPath;
import std.stdio : stdout, File, writeln, writefln;
import std.typecons : Yes, No;

import dextool.type;

import dextool.plugin.mutate.backend.database : Database, IterateMutantRow, MutationId;
import dextool.plugin.mutate.backend.generate_mutant : MakeMutationTextResult, makeMutationText;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.report.analyzers : reportMutationSubtypeStats,
    reportMarkedMutants, reportStatistics, MutationScoreHistory;
import dextool.plugin.mutate.backend.report.type : ReportEvent;
import dextool.plugin.mutate.backend.report.utility : window, windowSize, Table;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : ReportKind, ReportSection;
import dextool.plugin.mutate.backend.utility : Profile;

@safe:

void report(ref Database db, const ConfigReport conf, FilesysIO fio) {
    import dextool.plugin.mutate.backend.utility : Profile;
    import dextool.plugin.mutate.backend.mutation_type : toInternal;

    auto a = new ReportPlain(conf, fio);

    {
        auto profile = Profile("iterate mutants for report");
        void iter(const ref IterateMutantRow row) {
            a.locationEvent(db, row);
        }

        db.iterateMutants(&iter);
    }

    auto profile = Profile("post process report");
    a.locationStatEvent;
    a.statEvent(db);
}

/** Report mutations in a format easily readable by a human.
 */
@safe final class ReportPlain {
    import std.array : Appender;
    import dextool.plugin.mutate.backend.utility;
    import my.set;

    const ConfigReport conf;
    Set!ReportSection sections;
    FilesysIO fio;

    long[MakeMutationTextResult] mutationStat;

    this(const ConfigReport conf, FilesysIO fio) {
        this.fio = fio;
        this.conf = conf;
        this.sections = conf.reportSection.toSet;
    }

    void locationEvent(ref Database db, const ref IterateMutantRow r) @trusted {
        void report() {
            MakeMutationTextResult mut_txt;
            AbsolutePath abs_path;
            try {
                abs_path = AbsolutePath(buildPath(fio.getOutputDir, r.file.Path));
                mut_txt = makeMutationText(fio.makeInput(abs_path),
                        r.mutationPoint.offset, r.mutation.kind, r.lang);
            } catch (Exception e) {
                logger.warning(e.msg);
            }

            logger.infof("%s %s from '%s' to '%s' %s in %s:%s:%s", r.id.get,
                    r.mutation.status, mut_txt.original, mut_txt.mutation,
                    r.attrs, abs_path, r.sloc.line, r.sloc.column);
        }

        void updateMutationStat() {
            if (r.mutation.status != Mutation.Status.alive)
                return;

            try {
                auto abs_path = AbsolutePath(buildPath(fio.getOutputDir, r.file.Path));
                auto mut_txt = makeMutationText(fio.makeInput(abs_path),
                        r.mutationPoint.offset, r.mutation.kind, r.lang);

                if (auto v = mut_txt in mutationStat)
                    ++(*v);
                else
                    mutationStat[mut_txt] = 1;
            } catch (Exception e) {
                logger.warning(e.msg);
            }
        }

        void updateTestCaseStat(TestCase[] testCases) {
            if (r.mutation.status != Mutation.Status.killed || testCases.empty)
                return;

            try {
                auto abs_path = AbsolutePath(buildPath(fio.getOutputDir, r.file.Path));
                auto mut_txt = makeMutationText(fio.makeInput(abs_path),
                        r.mutationPoint.offset, r.mutation.kind, r.lang);
            } catch (Exception e) {
                logger.warning(e.msg);
            }
        }

        void reportTestCase(TestCase[] testCases) {
            if (r.mutation.status != Mutation.Status.killed || testCases.empty)
                return;
            logger.infof("%s killed by [%(%s, %)]", r.id.get, testCases);
        }

        try {
            if (ReportSection.alive in sections && r.mutation.status == Mutation.Status.alive)
                report;

            if (ReportSection.killed in sections && r.mutation.status == Mutation.Status.killed)
                report;

            if (ReportSection.all_mut in sections)
                report;

            if (ReportSection.mut_stat in sections)
                updateMutationStat;

            auto testCases = () {
                if (ReportSection.tc_killed in sections || ReportSection.tc_stat in sections) {
                    return db.testCaseApi.getTestCases(r.id);
                }
                return null;
            }();

            if (ReportSection.tc_killed in sections)
                reportTestCase(testCases);

            if (ReportSection.tc_stat in sections)
                updateTestCaseStat(testCases);
        } catch (Exception e) {
            logger.trace(e.msg).collectException;
        }
    }

    void locationStatEvent() {
        if (ReportSection.mut_stat in sections && mutationStat.length != 0) {
            logger.info("Alive Mutation Statistics");

            Table!4 substat_tbl;

            substat_tbl.heading = ["Percentage", "Count", "From", "To"];
            reportMutationSubtypeStats(mutationStat, substat_tbl);

            writeln(substat_tbl);
        }
    }

    void statEvent(ref Database db) {
        import dextool.plugin.mutate.backend.report.analyzers : reportTestCaseFullOverlap,
            reportTestCaseStats, reportDeadTestCases, toTable, reportMutationScoreHistory;

        auto stdout_ = () @trusted { return stdout; }();

        if (ReportSection.tc_stat in sections) {
            logger.info("Test Case Kill Statistics");
            Table!3 tc_tbl;

            tc_tbl.heading = ["Percentage", "Count", "TestCase"];
            auto r = reportTestCaseStats(db);
            r.toTable(conf.tcKillSortNum, conf.tcKillSortOrder, tc_tbl);

            writeln(tc_tbl);
        }

        if (ReportSection.tc_killed_no_mutants in sections) {
            logger.info("Test Case(s) that has killed no mutants");
            auto r = reportDeadTestCases(db);
            if (r.ratio > 0)
                writefln("%s/%s = %s of all test cases", r.numDeadTC, r.total, r.ratio);

            Table!2 tbl;
            tbl.heading = ["TestCase", "Location"];
            r.toTable(tbl);
            writeln(tbl);
        }

        if (ReportSection.tc_full_overlap in sections
                || ReportSection.tc_full_overlap_with_mutation_id in sections) {
            auto stat = reportTestCaseFullOverlap(db);

            if (ReportSection.tc_full_overlap in sections) {
                logger.info("Redundant Test Cases (killing the same mutants)");
                Table!2 tbl;
                stat.toTable!(No.colWithMutants)(tbl);
                tbl.heading = ["TestCase", "Count"];
                writeln(stat.sumToString);
                writeln(tbl);
            }

            if (ReportSection.tc_full_overlap_with_mutation_id in sections) {
                logger.info("Redundant Test Cases (killing the same mutants)");
                Table!3 tbl;
                stat.toTable!(Yes.colWithMutants)(tbl);
                tbl.heading = ["TestCase", "Count", "Mutation ID"];
                writeln(stat.sumToString);
                writeln(tbl);
            }
        }

        if (ReportSection.marked_mutants in sections) {
            logger.info("Marked mutants");
            auto r = reportMarkedMutants(db);
            writeln(r.tbl);
        }

        if (ReportSection.trend in sections) {
            logger.info("Mutation Score History");
            auto r = reportMutationScoreHistory(db);
            writeln(.toTable(r));
        }

        if (ReportSection.summary in sections) {
            logger.info("Summary");
            auto summary = reportStatistics(db);
            writeln(summary.toString);

            syncStatus(db);
        }

        writeln;
    }
}

private:

Table!2 toTable(MutationScoreHistory data) {
    Table!2 tbl;
    tbl.heading = ["Date", "Score"];
    foreach (a; data.data) {
        typeof(tbl).Row row = [a.timeStamp.to!string, a.score.get.to!string];
        tbl.put(row);
    }

    return tbl;
}

void syncStatus(ref Database db) {
    import std.algorithm : sort;
    import std.typecons : tuple;
    import dextool.plugin.mutate.backend.report.analyzers : reportSyncStatus;

    auto status = reportSyncStatus(db, 1);
    if (status.mutants.empty)
        return;

    if (status.mutants[0].updated > status.code && status.mutants[0].updated > status.test) {
        return;
    }

    logger.info("Sync Status");

    Table!2 tbl;
    tbl.heading = ["Type", "Updated"];
    foreach (r; [
        tuple("Test", status.test), tuple("Code", status.code),
        tuple("Coverage", status.coverage),
        tuple("Oldest Mutant", status.mutants[0].updated)
    ].sort!((a, b) => a[1] < b[1])) {
        typeof(tbl).Row row = [r[0], r[1].to!string];
        tbl.put(row);
    }
    writeln(tbl);
}
