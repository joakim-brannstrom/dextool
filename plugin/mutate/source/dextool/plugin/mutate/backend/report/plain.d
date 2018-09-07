/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

#SPC-plugin_mutate_report_for_human_plain
*/
module dextool.plugin.mutate.backend.report.plain;

import std.exception : collectException;
import logger = std.experimental.logger;

import dextool.type;

import dextool.plugin.mutate.type : MutationKind, ReportKind, ReportLevel,
    ReportSection;
import dextool.plugin.mutate.backend.database : Database, IterateMutantRow,
    MutationId;
import dextool.plugin.mutate.backend.interface_ : FilesysIO, SafeInput;
import dextool.plugin.mutate.backend.type : Mutation;

import dextool.plugin.mutate.backend.report.utility : MakeMutationTextResult,
    makeMutationText, Table, reportMutationSubtypeStats, reportStatistics,
    reportTestCaseStats, MutationsMap, reportTestCaseKillMap, MutationReprMap,
    MutationRepr, reportMutationTestCaseSuggestion, reportDeadTestCases;
import dextool.plugin.mutate.backend.report.type : ReportEvent;

@safe:

/** Report mutations in a format easily readable by a human.
 */
@safe final class ReportPlain : ReportEvent {
    import std.array : Appender;
    import dextool.plugin.mutate.backend.utility;

    const Mutation.Kind[] kinds;
    bool[ReportSection] sections;
    FilesysIO fio;

    long[MakeMutationTextResult] mutationStat;
    long[TestCase] testCaseStat;

    MutationsMap testCaseMutationKilled;
    MutationReprMap mutationReprMap;
    Appender!(MutationId[]) testCaseSuggestions;

    this(const Mutation.Kind[] kinds, const ReportLevel report_level,
            const ReportSection[] sections, FilesysIO fio) {
        this.kinds = kinds;
        this.fio = fio;

        ReportSection[] tmp_sec;
        if (sections.length == 0) {
            final switch (report_level) with (ReportSection) {
            case ReportLevel.summary:
                tmp_sec = [summary, mut_stat];
                break;
            case ReportLevel.alive:
                tmp_sec = [summary, mut_stat, alive];
                break;
            case ReportLevel.all:
                tmp_sec = [summary, mut_stat, all_mut, tc_killed];
                break;
            }
        } else {
            tmp_sec = sections.dup;
        }

        import std.algorithm : each;

        tmp_sec.each!(a => this.sections[a] = true);
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

            logger.infof("%s %s from '%s' to '%s' in %s:%s:%s", r.id, r.mutation.status,
                    mut_txt.original, mut_txt.mutation, abs_path, r.sloc.line, r.sloc.column);
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

                foreach (const a; r.testCases) {
                    if (auto v = a in testCaseStat) {
                        ++(*v);
                    } else {
                        testCaseStat[a] = 1;
                    }
                }
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
            if (ReportSection.alive in sections) {
                if (r.mutation.status == Mutation.Status.alive) {
                    report();
                }
            }

            if (ReportSection.killed in sections) {
                if (r.mutation.status == Mutation.Status.killed) {
                    report();
                }
            }

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
        import std.stdio : stdout, File, writeln;

        if (ReportSection.tc_stat in sections && testCaseStat.length != 0) {
            logger.info("Test Case Kill Statistics");

            long take_ = 20;
            if (ReportSection.all_mut in sections)
                take_ = 1024;

            Table!3 tc_tbl;

            tc_tbl.heading = ["Percentage", "Count", "TestCase"];
            const total = db.totalMutants(kinds);
            reportTestCaseStats(testCaseStat, total.isNull ? 1 : total.count, take_, tc_tbl);

            writeln(tc_tbl);
        }

        if (ReportSection.tc_killed_no_mutants in sections) {
            logger.info("Test Case(s) that has killed no mutants");

            Table!2 tbl;
            tbl.heading = ["TestCase", "Location"];

            reportDeadTestCases(db.getTestCasesWithZeroKills, tbl);
            writeln(tbl);
        }

        if (ReportSection.tc_suggestion in sections && testCaseSuggestions.data.length != 0) {
            static void writer(ref Table!1 tbl) {
                writeln(tbl);
            }

            reportMutationTestCaseSuggestion(db, testCaseSuggestions.data, &writer);
        }

        if (ReportSection.summary in sections) {
            logger.info("Summary");
            auto stdout_ = () @trusted{ return stdout; }();
            struct Log {
                File stdout;
                alias stdout this;

                void tracef(ARGS...)(auto ref ARGS args) {
                    stdout.writef(args);
                }
            }

            auto log = Log(stdout_);
            reportStatistics(db, kinds, log);
        }

        writeln;
    }
}
