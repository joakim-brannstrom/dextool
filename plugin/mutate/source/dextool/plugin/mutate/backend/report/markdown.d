/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

#SPC-plugin_mutate_report_for_human
*/
module dextool.plugin.mutate.backend.report.markdown;

import std.exception : collectException;
import logger = std.experimental.logger;

import dextool.type;

import dextool.plugin.mutate.type : MutationKind, ReportKind, ReportLevel;
import dextool.plugin.mutate.backend.database : Database, IterateMutantRow;
import dextool.plugin.mutate.backend.interface_ : FilesysIO, SafeInput;
import dextool.plugin.mutate.backend.type : Mutation, Offset;

import dextool.plugin.mutate.backend.report.utility : MakeMutationTextResult,
    makeMutationText, window, windowSize;
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
    const ReportLevel report_level;
    FilesysIO fio;

    Markdown!(SimpleWriter, SimpleWriter) markdown;
    Markdown!(SimpleWriter, SimpleWriter) markdown_loc;
    Markdown!(SimpleWriter, SimpleWriter) markdown_sum;

    Table!5 mut_tbl;
    alias Row = Table!(5).Row;

    long[MakeMutationTextResult] mutationStat;

    alias Writer = function(const(char)[] s) { import std.stdio : write;

    write(s); };

    this(Mutation.Kind[] kinds, ReportLevel report_level, FilesysIO fio) {
        this.kinds = kinds;
        this.report_level = report_level;
        this.fio = fio;
    }

    override void mutationKindEvent(const MutationKind[] kind_) {
        auto writer = delegate(const(char)[] s) {
            import std.stdio : write;

            write(s);
        };

        SimpleWriter tracer;
        if (report_level == ReportLevel.all) {
            tracer = writer;
        } else {
            tracer = delegate(const(char)[] s) {  };
        }

        markdown = Markdown!(SimpleWriter, SimpleWriter)(writer, tracer);
        markdown = markdown.heading("Mutation Type %(%s, %)", kind_);
    }

    override void locationStartEvent() {
        if (report_level == ReportLevel.summary)
            return;
        markdown_loc = markdown.heading("Mutants");
        mut_tbl.heading = ["From", "To", "File Line:Column", "ID", "Status"];
    }

    override void locationEvent(const ref IterateMutantRow r) @trusted {
        void report() {
            MakeMutationTextResult mut_txt;
            try {
                auto abs_path = AbsolutePath(FileName(r.file), DirName(fio.getOutputDir));
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

        try {
            final switch (report_level) {
            case ReportLevel.summary:
                break;
            case ReportLevel.alive:
                if (r.mutation.status == Mutation.Status.alive) {
                    report();
                }
                break;
            case ReportLevel.all:
                report();
                break;
            }
        }
        catch (Exception e) {
            logger.trace(e.msg).collectException;
        }
    }

    override void locationEndEvent() {
        if (report_level == ReportLevel.summary)
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
        if (mutationStat.length != 0 && report_level != ReportLevel.summary) {
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
        markdown_sum = markdown.heading("Summary");

        markdown_sum.beginSyntaxBlock;
        reportStatistics(db, kinds, markdown_sum);
        markdown_sum.endSyntaxBlock;

        markdown_sum.popHeading;
    }
}

private:

struct Table(int columnsNr) {
    alias Row = string[columnsNr];

    Row heading_;
    Row[] rows;
    ulong[columnsNr] columnWidth;

    this(const Row heading) {
        this.heading = heading;
        updateColumns(heading);
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
        import std.range : enumerate;
        import std.algorithm : filter, each;

        foreach (a; r[].enumerate.filter!(a => a.value.length > columnWidth[a.index])) {
            columnWidth[a.index] = a.value.length;
        }
    }
}

void reportMutationSubtypeStats(ref const long[MakeMutationTextResult] mut_stat, ref Table!4 tbl) @safe nothrow {
    import std.conv : to;
    import std.format : format;
    import std.algorithm : sum, map, sort, filter;

    // trusted because it is @safe in dmd-2.078.1
    // TODO remove the trusted wrapper
    long total = () @trusted{ return mut_stat.byValue.sum; }();

    import std.array : array;
    import std.range : take;
    import std.typecons : Tuple;

    // trusted because it is marked as @safe in dmd-2.078.1
    // TODO remove this trusted when upgrading the minimal compiler
    // can be simplified to:
    // foreach (v, alive.byKeyValue.array.sort!((a, b) => a.value > b.value))....
    auto kv = () @trusted{
        return mut_stat.byKeyValue.array.sort!((a, b) => a.value > b.value)
            .take(20).map!(a => Tuple!(MakeMutationTextResult, "key", long,
                    "value")(a.key, a.value)).array;
    }();

    foreach (v; kv) {
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
        }
        catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }
}

void reportStatistics(ReportT)(ref Database db, const Mutation.Kind[] kinds, ref ReportT item) @safe nothrow {
    import core.time : dur;
    import std.algorithm : map, filter, sum;
    import std.range : only;
    import std.datetime : Clock;
    import dextool.plugin.mutate.backend.utility;

    auto alive = db.aliveMutants(kinds);
    auto killed = db.killedMutants(kinds);
    auto timeout = db.timeoutMutants(kinds);
    auto untested = db.unknownMutants(kinds);
    auto killed_by_compiler = db.killedByCompilerMutants(kinds);

    try {
        immutable align_ = 8;

        const auto total_time = only(alive, killed, timeout).filter!(a => !a.isNull)
            .map!(a => a.time.total!"msecs").sum.dur!"msecs";
        const auto total_cnt = only(alive, killed, timeout).filter!(a => !a.isNull)
            .map!(a => a.count).sum;
        const auto killed_cnt = only(killed, timeout).filter!(a => !a.isNull)
            .map!(a => a.count).sum;
        const auto untested_cnt = untested.isNull ? 0 : untested.count;
        const auto predicted = total_cnt > 0 ? (untested_cnt * (total_time / total_cnt))
            : 0.dur!"msecs";

        // execution time
        if (untested_cnt > 0 && predicted > 0.dur!"msecs")
            item.writefln("Predicted time until mutation testing is done: %s (%s)",
                    predicted, Clock.currTime + predicted);
        item.writefln("%-*s %s", align_ * 4, "Mutation execution time:", total_time);
        if (!killed_by_compiler.isNull)
            item.tracef("%-*s %s", align_ * 4, "Mutants killed by compiler:",
                    killed_by_compiler.time);

        item.writeln("");

        // mutation score and details
        if (!untested.isNull && untested.count > 0)
            item.writefln("Untested: %s", untested.count);
        if (!alive.isNull)
            item.writefln("%-*s %s", align_, "Alive:", alive.count);
        if (!killed.isNull)
            item.writefln("%-*s %s", align_, "Killed:", killed.count);
        if (!timeout.isNull)
            item.writefln("%-*s %s", align_, "Timeout:", timeout.count);
        item.writefln("%-*s %s", align_, "Total:", total_cnt);
        if (total_cnt > 0)
            item.writefln("%-*s %s", align_, "Score:",
                    cast(double) killed_cnt / cast(double) total_cnt);
        if (!killed_by_compiler.isNull)
            item.tracef("%-*s %s", align_, "Killed by compiler:", killed_by_compiler.count);
    }
    catch (Exception e) {
        logger.warning(e.msg).collectException;
    }
}
