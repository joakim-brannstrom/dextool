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

import dextool.plugin.mutate.type : MutationKind, ReportKind, ReportLevel;
import dextool.plugin.mutate.backend.database : Database, IterateMutantRow;
import dextool.plugin.mutate.backend.interface_ : FilesysIO, SafeInput;
import dextool.plugin.mutate.backend.type : Mutation;

import dextool.plugin.mutate.backend.report.utility : MakeMutationTextResult,
    makeMutationText, Table, reportMutationSubtypeStats, reportStatistics,
    reportTestCaseStats;
import dextool.plugin.mutate.backend.report.type : ReportEvent;

@safe:

/** Report mutations in a format easily readable by a human.
 */
@safe final class ReportPlain : ReportEvent {
    import dextool.plugin.mutate.backend.utility;

    const Mutation.Kind[] kinds;
    const ReportLevel report_level;
    FilesysIO fio;

    long[MakeMutationTextResult] mutationStat;
    long[TestCase] testCaseStat;

    this(Mutation.Kind[] kinds, ReportLevel report_level, FilesysIO fio) {
        this.kinds = kinds;
        this.report_level = report_level;
        this.fio = fio;
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
                        r.mutationPoint.offset, r.mutation.kind);

                if (r.mutation.status == Mutation.Status.alive) {
                    if (auto v = mut_txt in mutationStat)
                        ++(*v);
                    else
                        mutationStat[mut_txt] = 1;
                }
            }
            catch (Exception e) {
                logger.warning(e.msg);
            }

            logger.infof("%s %s from '%s' to '%s' in %s:%s:%s", r.id, r.mutation.status,
                    mut_txt.original, mut_txt.mutation, abs_path, r.sloc.line, r.sloc.column);
        }

        void updateTestCaseStat() {
            if (r.mutation.status != Mutation.Status.killed || r.testCases.length == 0)
                return;

            foreach (const a; r.testCases) {
                if (auto v = a in testCaseStat) {
                    ++(*v);
                } else {
                    testCaseStat[a] = 1;
                }
            }
        }

        void reportTestCase() {
            if (r.mutation.status != Mutation.Status.killed || r.testCases.length == 0)
                return;
            logger.infof("%s killed by [%(%s, %)]", r.id, r.testCases);
        }

        try {
            final switch (report_level) {
            case ReportLevel.summary:
                break;
            case ReportLevel.alive:
                if (r.mutation.status == Mutation.Status.alive) {
                    report();
                }
                updateTestCaseStat();
                break;
            case ReportLevel.all:
                updateTestCaseStat();
                report();
                reportTestCase();
                break;
            }
        }
        catch (Exception e) {
            logger.trace(e.msg).collectException;
        }
    }

    override void locationEndEvent() {
    }

    override void locationStatEvent() {
        import std.stdio : writeln;

        if (mutationStat.length != 0 && report_level != ReportLevel.summary) {
            logger.info("Alive Mutation Statistics");

            Table!4 substat_tbl;

            substat_tbl.heading = ["Percentage", "Count", "From", "To"];
            reportMutationSubtypeStats(mutationStat, substat_tbl);

            writeln(substat_tbl);
        }

        if (testCaseStat.length != 0 && report_level != ReportLevel.summary) {
            logger.info("Test Case Kill Statistics");

            long take_ = report_level == ReportLevel.all ? 1024 : 20;

            Table!3 tc_tbl;

            tc_tbl.heading = ["Percentage", "Count", "TestCase"];
            reportTestCaseStats(testCaseStat, tc_tbl, take_);

            writeln(tc_tbl);
        }
    }

    override void statEvent(ref Database db) {
        import std.stdio : stdout, File, writeln;

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
        writeln;
    }
}
