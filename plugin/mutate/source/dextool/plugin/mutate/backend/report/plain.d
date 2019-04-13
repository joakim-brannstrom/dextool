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
import std.exception : collectException;
import std.typecons : Yes, No;

import dextool.type;

import dextool.plugin.mutate.backend.database : Database, IterateMutantRow, MutationId;
import dextool.plugin.mutate.backend.interface_ : FilesysIO, SafeInput;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind, ReportKind, ReportLevel, ReportSection;

import dextool.plugin.mutate.backend.report.utility : MakeMutationTextResult,
    makeMutationText, Table, reportMutationSubtypeStats,
    reportStatistics, MutationsMap, reportTestCaseKillMap, MutationReprMap,
    MutationRepr, toSections;
import dextool.plugin.mutate.backend.report.type : ReportEvent;

@safe:

/** Report mutations in a format easily readable by a human.
 *
 * TODO: use dextool.set for sections.
 */
@safe final class ReportPlain : ReportEvent {
    import std.array : Appender;
    import dextool.plugin.mutate.backend.utility;

    const Mutation.Kind[] kinds;
    const ConfigReport conf;
    bool[ReportSection] sections;
    FilesysIO fio;

    long[MakeMutationTextResult] mutationStat;

    MutationsMap testCaseMutationKilled;
    MutationReprMap mutationReprMap;
    Appender!(MutationId[]) testCaseSuggestions;

    this(const Mutation.Kind[] kinds, const ConfigReport conf, FilesysIO fio) {
        this.kinds = kinds;
        this.fio = fio;
        this.conf = conf;

        ReportSection[] tmp_sec = conf.reportSection.length == 0
            ? conf.reportLevel.toSections : conf.reportSection.dup;

        foreach (a; tmp_sec)
            this.sections[a] = true;
    }

    override void mutationKindEvent(const MutationKind[] kind_) {
    }

    override void locationStartEvent() {
    }

    override void locationEvent(const ref IterateMutantRow r) @trusted {
        void report() {
            MakeMutationTextResult mut_txt;
            AbsolutePath abs_path;
            try {
                abs_path = AbsolutePath(FileName(r.file), DirName(fio.getOutputDir));
                mut_txt = makeMutationText(fio.makeInput(abs_path),
                        r.mutationPoint.offset, r.mutation.kind, r.lang);
            } catch (Exception e) {
                logger.warning(e.msg);
            }

            logger.infof("%s %s from '%s' to '%s' in %s:%s:%s [%(%s, %)]", r.id,
                    r.mutation.status, mut_txt.original, mut_txt.mutation,
                    abs_path, r.sloc.line, r.sloc.column, r.attrs);
        }

        void updateMutationStat() {
            if (r.mutation.status != Mutation.Status.alive)
                return;

            try {
                auto abs_path = AbsolutePath(FileName(r.file), DirName(fio.getOutputDir));
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

        void updateTestCaseStat() {
            if (r.mutation.status != Mutation.Status.killed || r.testCases.length == 0)
                return;

            try {
                auto abs_path = AbsolutePath(FileName(r.file), DirName(fio.getOutputDir));
                auto mut_txt = makeMutationText(fio.makeInput(abs_path),
                        r.mutationPoint.offset, r.mutation.kind, r.lang);
            } catch (Exception e) {
                logger.warning(e.msg);
            }
        }

        void updateTestCaseMap() {
            if (r.mutation.status != Mutation.Status.killed || r.testCases.length == 0)
                return;

            try {
                auto abs_path = AbsolutePath(FileName(r.file), DirName(fio.getOutputDir));
                auto mut_txt = makeMutationText(fio.makeInput(abs_path),
                        r.mutationPoint.offset, r.mutation.kind, r.lang);
                mutationReprMap[r.id] = MutationRepr(r.sloc, r.file, mut_txt);

                foreach (const a; r.testCases) {
                    testCaseMutationKilled[a][r.id] = true;
                }
            } catch (Exception e) {
                logger.warning(e.msg);
            }
        }

        void updateTestCaseSuggestion() {
            if (r.mutation.status == Mutation.Status.alive)
                testCaseSuggestions.put(r.id);
        }

        void reportTestCase() {
            if (r.mutation.status != Mutation.Status.killed || r.testCases.length == 0)
                return;
            logger.infof("%s killed by [%(%s, %)]", r.id, r.testCases);
        }

        try {
            if (ReportSection.alive in sections && r.mutation.status == Mutation.Status.alive)
                report();

            if (ReportSection.killed in sections && r.mutation.status == Mutation.Status.killed)
                report();

            if (ReportSection.all_mut in sections)
                report;

            if (ReportSection.mut_stat in sections)
                updateMutationStat;

            if (ReportSection.tc_killed in sections)
                reportTestCase;

            if (ReportSection.tc_stat in sections)
                updateTestCaseStat();

            if (ReportSection.tc_map in sections)
                updateTestCaseMap;

            if (ReportSection.tc_suggestion in sections)
                updateTestCaseSuggestion;
        } catch (Exception e) {
            logger.trace(e.msg).collectException;
        }
    }

    override void locationEndEvent() {
    }

    override void locationStatEvent() {
        import std.stdio : writeln;

        if (ReportSection.tc_map in sections && testCaseMutationKilled.length != 0) {
            logger.info("Test Case Kill Map");

            static void txtWriter(string s) {
                writeln(s);
            }

            static void writer(ref Table!4 tbl) {
                writeln(tbl);
            }

            reportTestCaseKillMap(testCaseMutationKilled, mutationReprMap, &txtWriter, &writer);
        }

        if (ReportSection.mut_stat in sections && mutationStat.length != 0) {
            logger.info("Alive Mutation Statistics");

            Table!4 substat_tbl;

            substat_tbl.heading = ["Percentage", "Count", "From", "To"];
            reportMutationSubtypeStats(mutationStat, substat_tbl);

            writeln(substat_tbl);
        }
    }

    override void statEvent(ref Database db) {
        import std.stdio : stdout, File, writeln, writefln;
        import dextool.plugin.mutate.backend.report.utility : reportTestCaseFullOverlap,
            reportTestCaseStats, reportMutationTestCaseSuggestion, reportDeadTestCases, toTable;

        auto stdout_ = () @trusted { return stdout; }();

        if (ReportSection.tc_stat in sections) {
            logger.info("Test Case Kill Statistics");
            Table!3 tc_tbl;

            tc_tbl.heading = ["Percentage", "Count", "TestCase"];
            const total = db.totalMutants(kinds);
            reportTestCaseStats(db, kinds, conf.tcKillSortNum, conf.tcKillSortOrder, tc_tbl);

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

        if (ReportSection.tc_suggestion in sections && testCaseSuggestions.data.length != 0) {
            static void writer(ref Table!1 tbl) {
                writeln(tbl);
            }

            reportMutationTestCaseSuggestion(db, testCaseSuggestions.data, &writer);
        }

        if (ReportSection.tc_full_overlap in sections
                || ReportSection.tc_full_overlap_with_mutation_id in sections) {
            auto stat = reportTestCaseFullOverlap(db, kinds);

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

        if (ReportSection.summary in sections) {
            logger.info("Summary");
            writeln(reportStatistics(db, kinds).toString);
        }

        writeln;
    }
}
