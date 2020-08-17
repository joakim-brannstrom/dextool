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
import std.exception : collectException;
import std.typecons : Yes, No;
import std.path : buildPath;

import dextool.type;

import dextool.plugin.mutate.backend.database : Database, IterateMutantRow, MutationId;
import dextool.plugin.mutate.backend.generate_mutant : MakeMutationTextResult, makeMutationText;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.report.analyzers : reportMutationSubtypeStats, reportMarkedMutants,
    reportStatistics, MutationsMap, reportTestCaseKillMap, MutationReprMap, MutationRepr;
import dextool.plugin.mutate.backend.report.type : ReportEvent;
import dextool.plugin.mutate.backend.report.utility : window, windowSize, Table, toSections;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind, ReportKind, ReportLevel, ReportSection;

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
        import std.stdio : writefln;

        writefln("Mutation operators: %(%s, %)", kind_);
    }

    override void locationStartEvent(ref Database db) @safe {
    }

    override void locationEvent(ref Database db, const ref IterateMutantRow r) @trusted {
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

            logger.infof("%s %s from '%s' to '%s' %s in %s:%s:%s", r.id, r.mutation.status,
                    mut_txt.original, mut_txt.mutation, r.attrs, abs_path,
                    r.sloc.line, r.sloc.column);
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

        void updateTestCaseMap(TestCase[] testCases) {
            if (r.mutation.status != Mutation.Status.killed || testCases.empty)
                return;

            try {
                auto abs_path = AbsolutePath(buildPath(fio.getOutputDir, r.file.Path));
                auto mut_txt = makeMutationText(fio.makeInput(abs_path),
                        r.mutationPoint.offset, r.mutation.kind, r.lang);
                mutationReprMap[r.id] = MutationRepr(r.sloc, r.file, mut_txt);

                foreach (const a; testCases) {
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

        void reportTestCase(TestCase[] testCases) {
            if (r.mutation.status != Mutation.Status.killed || testCases.empty)
                return;
            logger.infof("%s killed by [%(%s, %)]", r.id, testCases);
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
                if (ReportSection.tc_killed in sections
                        || ReportSection.tc_stat in sections || ReportSection.tc_map in sections) {
                    return db.getTestCases(r.id);
                }
                return null;
            }();

            if (ReportSection.tc_killed in sections)
                reportTestCase(testCases);

            if (ReportSection.tc_stat in sections)
                updateTestCaseStat(testCases);

            if (ReportSection.tc_map in sections)
                updateTestCaseMap(testCases);

            if (ReportSection.tc_suggestion in sections)
                updateTestCaseSuggestion();
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
        import dextool.plugin.mutate.backend.report.analyzers : reportTestCaseFullOverlap,
            reportTestCaseStats, reportMutationTestCaseSuggestion, reportDeadTestCases, toTable;

        auto stdout_ = () @trusted { return stdout; }();

        if (ReportSection.tc_stat in sections) {
            logger.info("Test Case Kill Statistics");
            Table!3 tc_tbl;

            tc_tbl.heading = ["Percentage", "Count", "TestCase"];
            auto r = reportTestCaseStats(db, kinds);
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

        if (ReportSection.marked_mutants in sections) {
            logger.info("Marked mutants");
            auto r = reportMarkedMutants(db, kinds);
            writeln(r.tbl);
        }

        if (ReportSection.summary in sections) {
            logger.info("Summary");
            writeln(reportStatistics(db, kinds).toString);
        }

        writeln;
    }
}
