/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

#SPC-report_for_human
*/
module dextool.plugin.mutate.backend.report.markdown;

import logger = std.experimental.logger;
import std.array : empty;
import std.exception : collectException;
import std.typecons : Yes, No;

import dextool.plugin.mutate.backend.database : Database, IterateMutantRow;
import dextool.plugin.mutate.backend.interface_ : FilesysIO, SafeInput;
import dextool.plugin.mutate.backend.type : Mutation, Offset;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind, ReportKind, ReportLevel,
    ReportSection;
import dextool.set;
import dextool.type;

import dextool.plugin.mutate.backend.report.utility : MakeMutationTextResult,
    makeMutationText, window, windowSize, reportMutationSubtypeStats,
    reportStatistics, Table, toSections;
import dextool.plugin.mutate.backend.report.type : SimpleWriter, ReportEvent;

@safe:

struct Markdown(Writer, TraceWriter) {
    import std.ascii : newline;
    import std.format : formattedWrite, format;
    import std.range : put;

    private int curr_head;
    private Writer w;
    private TraceWriter w_trace;

    private this(int heading, Writer w, TraceWriter w_trace) {
        this.curr_head = heading;
        this.w = w;
        this.w_trace = w_trace;
    }

    this(Writer w, TraceWriter w_trace) {
        this.w = w;
        this.w_trace = w_trace;
    }

    auto heading(ARGS...)(auto ref ARGS args) {
        import std.algorithm : copy;
        import std.range : repeat, take;

        repeat('#').take(curr_head + 1).copy(w);
        put(w, " ");
        formattedWrite(w, args);

        // two newlines because some markdown parsers do not correctly identify
        // a heading if it isn't separated
        put(w, newline);
        put(w, newline);
        return (typeof(this)(curr_head + 1, w, w_trace));
    }

    auto popHeading() {
        if (curr_head != 0)
            put(w, newline);
        return typeof(this)(curr_head - 1, w, w_trace);
    }

    auto beginSyntaxBlock(ARGS...)(auto ref ARGS args) {
        put(w, "```");
        static if (ARGS.length != 0)
            formattedWrite(w, args);
        put(w, newline);
        return this;
    }

    auto endSyntaxBlock() {
        put(w, "```");
        put(w, newline);
        return this;
    }

    void put(const(char)[] s) {
        write(s);
    }

    auto write(ARGS...)(auto ref ARGS args) {
        formattedWrite(w, "%s", args);
        return this;
    }

    auto writef(ARGS...)(auto ref ARGS args) {
        formattedWrite(w, args);
        return this;
    }

    auto writeln(ARGS...)(auto ref ARGS args) {
        this.write(args);
        put(w, newline);
        return this;
    }

    auto writefln(ARGS...)(auto ref ARGS args) {
        this.writef(args);
        put(w, newline);
        return this;
    }

    auto trace(ARGS...)(auto ref ARGS args) {
        this.writeln(w_trace, args);
        return this;
    }

    auto tracef(ARGS...)(auto ref ARGS args) {
        formattedWrite(w_trace, args);
        put(w_trace, newline);
        return this;
    }
}

/** Report mutations in a format easily readable by a human.
 */
@safe final class ReportMarkdown : ReportEvent {
    import std.conv : to;
    import std.format : format, FormatSpec;
    import dextool.plugin.mutate.backend.utility;

    static immutable col_w = 10;
    static immutable mutation_w = 10 + 8 + 8;

    const Mutation.Kind[] kinds;
    bool reportIndividualMutants;
    Set!ReportSection sections;
    FilesysIO fio;

    Markdown!(SimpleWriter, SimpleWriter) markdown;
    Markdown!(SimpleWriter, SimpleWriter) markdown_loc;
    Markdown!(SimpleWriter, SimpleWriter) markdown_sum;

    Table!5 mut_tbl;
    alias Row = Table!(5).Row;

    long[MakeMutationTextResult] mutationStat;

    alias Writer = function(const(char)[] s) { import std.stdio : write;

    write(s); };

    this(const Mutation.Kind[] kinds, const ConfigReport conf, FilesysIO fio) {
        this.kinds = kinds;
        this.fio = fio;

        ReportSection[] tmp_sec = conf.reportSection.length == 0
            ? conf.reportLevel.toSections : conf.reportSection.dup;

        sections = setFromList(tmp_sec);
        reportIndividualMutants = sections.contains(ReportSection.all_mut)
            || sections.contains(ReportSection.alive) || sections.contains(ReportSection.killed);
    }

    override void mutationKindEvent(const MutationKind[] kind_) {
        auto writer = delegate(const(char)[] s) {
            import std.stdio : write;

            write(s);
        };

        SimpleWriter tracer;
        if (ReportSection.all_mut)
            tracer = writer;
        else
            tracer = delegate(const(char)[] s) {  };

        markdown = Markdown!(SimpleWriter, SimpleWriter)(writer, tracer);
        markdown = markdown.heading("Mutation Type %(%s, %)", kind_);
    }

    override void locationStartEvent() {
        if (reportIndividualMutants) {
            markdown_loc = markdown.heading("Mutants");
            mut_tbl.heading = ["From", "To", "File Line:Column", "ID", "Status"];
        }
    }

    override void locationEvent(const ref IterateMutantRow r) @trusted {
        void report() {
            MakeMutationTextResult mut_txt;
            try {
                auto abs_path = AbsolutePath(FileName(r.file), DirName(fio.getOutputDir));
                mut_txt = makeMutationText(fio.makeInput(abs_path),
                        r.mutationPoint.offset, r.mutation.kind, r.lang);

                if (r.mutation.status == Mutation.Status.alive) {
                    if (auto v = mut_txt in mutationStat)
                        ++(*v);
                    else
                        mutationStat[mut_txt] = 1;
                }
            } catch (Exception e) {
                logger.warning(e.msg);
            }

            // dfmt off
            Row r_ = [
                format("`%s`", window(mut_txt.original, windowSize)),
                format("`%s`", window(mut_txt.mutation, windowSize)),
                format("%s %s:%s", r.file, r.sloc.line, r.sloc.column),
                r.id.to!string,
                r.mutation.status.to!string,
            ];
            mut_tbl.put(r_);
            // dfmt on
        }

        if (!reportIndividualMutants)
            return;

        try {
            if (sections.contains(ReportSection.alive)) {
                if (r.mutation.status == Mutation.Status.alive) {
                    report();
                }
            }

            if (sections.contains(ReportSection.killed)) {
                if (r.mutation.status == Mutation.Status.killed) {
                    report();
                }
            }

            if (sections.contains(ReportSection.all_mut))
                report();
        } catch (Exception e) {
            logger.trace(e.msg).collectException;
        }
    }

    override void locationEndEvent() {
        if (!reportIndividualMutants)
            return;

        auto writer = delegate(const(char)[] s) {
            import std.stdio : write;

            write(s);
        };

        import std.format : FormatSpec;

        auto fmt = FormatSpec!char("%s");
        mut_tbl.toString(writer, fmt);

        markdown_loc.popHeading;
    }

    override void locationStatEvent() {
        if (mutationStat.length != 0 && sections.contains(ReportSection.mut_stat)) {
            auto item = markdown.heading("Alive Mutation Statistics");

            Table!4 substat_tbl;
            Table!4.Row SRow;

            substat_tbl.heading = ["Percentage", "Count", "From", "To"];
            reportMutationSubtypeStats(mutationStat, substat_tbl);

            auto fmt = FormatSpec!char("%s");
            substat_tbl.toString(Writer, fmt);
            item.popHeading;
        }
    }

    override void statEvent(ref Database db) {
        import dextool.plugin.mutate.backend.report.utility : reportDeadTestCases,
            reportTestCaseFullOverlap, toTable;

        const fmt = FormatSpec!char("%s");

        if (sections.contains(ReportSection.tc_killed_no_mutants)) {
            auto item = markdown.heading("Test Cases with Zero Kills");
            auto r = reportDeadTestCases(db);

            if (r.ratio > 0)
                item.writefln("%s/%s = %s of all test cases", r.numDeadTC, r.total, r.ratio);

            Table!2 tbl;
            tbl.heading = ["TestCase", "Location"];
            r.toTable(tbl);
            tbl.toString(Writer, fmt);

            item.popHeading;
        }

        if (sections.contains(ReportSection.tc_full_overlap)) {
            Table!2 tbl;
            tbl.heading = ["TestCase", "Count"];
            auto stat = reportTestCaseFullOverlap(db, kinds);
            stat.toTable!(No.colWithMutants)(tbl);

            if (!tbl.empty) {
                auto item = markdown.heading("Redundant Test Cases (killing the same mutants)");
                stat.sumToString(item);
                item.writeln(stat);
                tbl.toString(Writer, fmt);
                item.popHeading;
            }
        }

        if (sections.contains(ReportSection.summary)) {
            markdown_sum = markdown.heading("Summary");

            markdown_sum.beginSyntaxBlock;
            markdown_sum.writefln(reportStatistics(db, kinds).toString);
            markdown_sum.endSyntaxBlock;

            markdown_sum.popHeading;
        }
    }
}
