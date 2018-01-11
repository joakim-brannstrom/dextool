/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains functionality for reporting the mutations. Both the
summary and details for each mutation.
*/
module dextool.plugin.mutate.backend.report;

import std.exception : collectException;
import logger = std.experimental.logger;

import dextool.type;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.interface_ : FilesysIO, SafeInput;
import dextool.plugin.mutate.type : MutationKind, ReportKind, ReportLevel;
import dextool.plugin.mutate.backend.type : Mutation;

ExitStatusType runReport(ref Database db, const MutationKind kind,
        const ReportKind report_kind, const ReportLevel report_level, FilesysIO fio) @safe nothrow {
    import std.stdio : write;
    import dextool.plugin.mutate.backend.utility;

    import d2sqlite3 : Row;

    const auto kinds = dextool.plugin.mutate.backend.utility.toInternal(kind);

    try {
        auto genrep = ReportGenerator.make(kind, report_kind, report_level, fio);
        genrep.mutationKindEvent(kind);

        genrep.locationStartEvent;
        db.iterateMutants(kinds, &genrep.locationEvent);
        genrep.locationEndEvent;

        genrep.statStartEvent;
        genrep.statEvent(db);
        genrep.statEndEvent;
    }
    catch (Exception e) {
        logger.error(e.msg).collectException;
    }

    return ExitStatusType.Ok;
}

@safe:
private:

// 5 because it covers all the operators and true/false
immutable windowSize = 5;

immutable originalIsCorrupt = "deXtool: unable to open the file or it has changed since mutation where performed";

/**
 * Expects the event to come in the following order:
 *  - mutationKindEvent
 *  - locationStartEvent
 *  - locationEvent
 *  - locationEndEvent
 *  - statStartEvent
 *  - statEvent
 *  - statEndEvent
 */
struct ReportGenerator {
    import std.algorithm : each;
    import d2sqlite3 : Row;

    ReportEvens[] listeners;

    static auto make(MutationKind kind, ReportKind report_kind,
            ReportLevel report_level, FilesysIO fio) {
        import dextool.plugin.mutate.backend.utility;

        auto kinds = dextool.plugin.mutate.backend.utility.toInternal(kind);
        ReportEvens[] listeners;
        final switch (report_kind) {
        case ReportKind.markdown:
            listeners = [new ReportMarkdown(kinds, report_level, fio)];
            break;
        case ReportKind.compiler:
            listeners = [new ReportCompiler(kinds, report_level, fio)];
            break;
        }
        return ReportGenerator(listeners);
    }

    void mutationKindEvent(MutationKind kind_) {
        listeners.each!(a => a.mutationKindEvent(kind_));
    }

    void locationStartEvent() {
        listeners.each!(a => a.locationStartEvent);
    }

    // trusted: trusting that d2sqlite3 and sqlite3 is memory safe.
    void locationEvent(ref Row r) @trusted {
        listeners.each!(a => a.locationEvent(r));
    }

    void locationEndEvent() {
        listeners.each!(a => a.locationEndEvent);
    }

    void statStartEvent() {
        listeners.each!(a => a.statStartEvent);
    }

    void statEvent(ref Database db) {
        listeners.each!(a => a.statEvent(db));
    }

    void statEndEvent() {
        listeners.each!(a => a.statEndEvent);
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

        if (untested_cnt > 0 && predicted > 0.dur!"msecs")
            item.writefln("Predicted time until mutation testing is done: %s (%s)",
                    predicted, Clock.currTime + predicted);
        if (!untested.isNull && untested.count > 0)
            item.writefln("Untested: %s", untested.count);
        if (!alive.isNull)
            item.writefln("%-*s %-*s (%s)", align_, "Alive:", align_, alive.count, alive.time);
        if (!killed.isNull)
            item.writefln("%-*s %-*s (%s)", align_, "Killed:", align_, killed.count, killed.time);
        if (!timeout.isNull)
            item.writefln("%-*s %-*s (%s)", align_, "Timeout:", align_,
                    timeout.count, timeout.time);
        item.writefln("%-*s %-*s (%s)", align_, "Total:", align_, total_cnt, total_time);
        if (total_cnt > 0)
            item.writefln("%-*s %-*s", align_, "Score:", align_,
                    cast(double) killed_cnt / cast(double) total_cnt);
        if (!killed_by_compiler.isNull)
            item.tracef("%-*s %-*s (%s)", align_, "Killed by compiler:",
                    align_, killed_by_compiler.count, killed_by_compiler.time);
    }
    catch (Exception e) {
        logger.error(e.msg).collectException;
    }
}

alias SimpleWriter = void delegate(const(char)[]) @safe;

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

struct CompilerConsole(Writer) {
    import std.ascii : newline;
    import std.format : formattedWrite, format;
    import std.range : put;

    private Writer w;

    this(Writer w) {
        this.w = w;
    }

    auto build() {
        return CompilerMsgBuilder!Writer(w);
    }
}

/** Build a compiler msg that follows how GCC would print to the console.
 *
 * Note that it should write to stderr.
 */
struct CompilerMsgBuilder(Writer) {
    import std.ascii : newline;
    import std.format : formattedWrite;
    import std.range : put;

    private {
        Writer w;
        string file_;
        long line_;
        long column_;
    }

    this(Writer w) {
        this.w = w;
    }

    auto file(string a) {
        file_ = a;
        return this;
    }

    auto line(long a) {
        line_ = a;
        return this;
    }

    auto column(long a) {
        column_ = a;
        return this;
    }

    auto begin(ARGS...)(auto ref ARGS args) {
        // for now the severity is hard coded to warning because nothing else
        // needs to be supported.
        formattedWrite(w, "%s:%s:%s: warning: ", file_, line_, column_);
        formattedWrite(w, args);
        put(w, newline);
        return this;
    }

    auto note(ARGS...)(auto ref ARGS args) {
        formattedWrite(w, "%s:%s:%s: note: ", file_, line_, column_);
        formattedWrite(w, args);
        put(w, newline);
        return this;
    }

    auto fixit(long offset, string mutation) {
        // Example of a fixit hint from gcc:
        // fix-it:"foo.cpp":{5:12-5:17}:"argc"
        // the second value in the location is bytes (starting from 1) from the
        // start of the line.
        formattedWrite(w, `fix-it:"%s":{%s:%s-%s:%s}:"%s"`, file_, line_,
                column_, line_, column_ + offset, mutation);
        put(w, newline);
        return this;
    }

    void end() {
    }
}

immutable invalidFile = "Dextool: Invalid UTF-8 content";

string toInternal(ubyte[] data) @safe nothrow {
    import std.utf : validate;

    try {
        auto result = () @trusted{ return cast(string) data; }();
        validate(result);
        return result;
    }
    catch (Exception e) {
    }

    return invalidFile;
}

/// Generic interface that a report event listeners shall implement.
@safe interface ReportEvens {
    import d2sqlite3 : Row;

    void mutationKindEvent(MutationKind);
    void locationStartEvent();
    void locationEvent(ref Row);
    void locationEndEvent();
    void statStartEvent();
    void statEvent(ref Database db);
    void statEndEvent();
}

/** Report mutations in a format easily readable by a human.
 *
 * #SPC-plugin_mutate_report_for_human
 */
@safe final class ReportMarkdown : ReportEvens {
    import std.conv : to;
    import std.format : format;
    import d2sqlite3 : Row;
    import dextool.plugin.mutate.backend.utility;

    static immutable col_w = 10;
    static immutable mutation_w = 10 + 8 + 8;

    const Mutation.Kind[] kinds;
    const ReportLevel report_level;
    FilesysIO fio;

    Markdown!(SimpleWriter, SimpleWriter) markdown;
    Markdown!(SimpleWriter, SimpleWriter) markdown_loc;
    Markdown!(SimpleWriter, SimpleWriter) markdown_sum;

    this(Mutation.Kind[] kinds, ReportLevel report_level, FilesysIO fio) {
        this.kinds = kinds;
        this.report_level = report_level;
        this.fio = fio;
    }

    override void mutationKindEvent(MutationKind kind_) {
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
        markdown = markdown.heading("Mutation Type %s", kind_);
    }

    override void locationStartEvent() {
        if (report_level == ReportLevel.summary)
            return;
        markdown_loc = markdown.heading("Locations");
        markdown_loc.writefln("%-*s %-*s %-*s %s", col_w, "ID", col_w,
                "Status", mutation_w, "Mutation", "Location");
        markdown_loc.beginSyntaxBlock;
    }

    override void locationEvent(ref Row r) @trusted {
        if (report_level == ReportLevel.summary)
            return;

        try {
            auto status = r.peek!int(1).to!(Mutation.Status);
            auto kind = r.peek!int(2).to!(Mutation.Kind);
            const id = r.peek!long(0);
            const file = r.peek!string(8);
            const line = r.peek!long(6);
            const column = r.peek!long(7);

            long[2] offs = [r.peek!long(4), r.peek!long(5)];

            MakeMutationTextResult mut_txt;
            if (report_level != ReportLevel.summary) {
                try {
                    auto abs_path = AbsolutePath(FileName(file), DirName(fio.getRestrictDir));
                    mut_txt = makeMutationText(fio.makeInput(abs_path), offs, kind);
                }
                catch (Exception e) {
                    logger.warning(e.msg);
                }
            }

            // dfmt off
            auto msg = format("%-*s %-*s %-*s %s %s:%s",
                              col_w, id,
                              col_w, status,
                              mutation_w, format("'%s' with '%s'",
                                                 window(mut_txt.original, windowSize),
                                                 window(mut_txt.mutation, windowSize)),
                              file, line, column);
            // dfmt on
            final switch (report_level) {
            case ReportLevel.summary:
                break;
            case ReportLevel.alive:
                if (status == Mutation.Status.alive) {
                    markdown.writeln(msg);
                }
                break;
            case ReportLevel.all:
                markdown.writeln(msg);
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

        markdown_loc.endSyntaxBlock;
        markdown_loc.popHeading;
    }

    override void statStartEvent() {
        markdown_sum = markdown.heading("Summary");
        markdown_sum.beginSyntaxBlock;
    }

    override void statEvent(ref Database db) {
        reportStatistics(db, kinds, markdown_sum);
    }

    override void statEndEvent() {
        markdown_sum.endSyntaxBlock;
        markdown_sum.popHeading;
    }
}

/** Report mutations as gcc would do for compilation warnings with fixit hints.
 *
 * #SPC-plugin_mutate_report_for_tool_integration
 */
@safe final class ReportCompiler : ReportEvens {
    import std.algorithm : each;
    import std.conv : to;
    import std.format : format;
    import d2sqlite3 : Row;
    import dextool.plugin.mutate.backend.utility;

    const Mutation.Kind[] kinds;
    const ReportLevel report_level;
    FilesysIO fio;

    CompilerConsole!SimpleWriter compiler;

    this(Mutation.Kind[] kinds, ReportLevel report_level, FilesysIO fio) {
        this.kinds = kinds;
        this.report_level = report_level;
        this.fio = fio;
    }

    override void mutationKindEvent(MutationKind) {
        compiler = CompilerConsole!SimpleWriter(delegate(const(char)[] s) @trusted{
            import std.stdio : stderr, write;

            stderr.write(s);
        });
    }

    override void locationStartEvent() {
    }

    override void locationEvent(ref Row r) @trusted {
        import dextool.plugin.mutate.backend.generate_mutant : makeMutation;

        try {
            auto status = r.peek!int(1).to!(Mutation.Status);
            auto kind = r.peek!int(2).to!(Mutation.Kind);
            const id = r.peek!long(0);
            const file = r.peek!string(8);
            const line = r.peek!long(6);
            const column = r.peek!long(7);

            long[2] offs = [r.peek!long(4), r.peek!long(5)];
            AbsolutePath abs_path;

            MakeMutationTextResult mut_txt;
            try {
                abs_path = AbsolutePath(FileName(file), DirName(fio.getRestrictDir));
                mut_txt = makeMutationText(fio.makeInput(abs_path), offs, kind);
            }
            catch (Exception e) {
                logger.warning(e.msg);
            }

            void report() {
                // dfmt off
                auto b = compiler.build
                    .file(abs_path)
                    .line(line)
                    .column(column)
                    .begin("%s: replace '%s' with '%s'", kind,
                           window(mut_txt.original, windowSize),
                           window(mut_txt.mutation, windowSize))
                    .note("status:%s id:%s", status, id);

                if (mut_txt.original.length > windowSize)
                    b = b.note("replace '%s'", mut_txt.original);
                if (mut_txt.mutation.length > windowSize)
                    b = b.note("with '%s'", mut_txt.mutation);

                b.fixit(offs[1] - offs[0], mut_txt.mutation)
                    .end;
                // dfmt on
            }

            // summary is the default and according to the specification of the
            // default for tool integration alive mutations shall be printed.
            final switch (report_level) {
            case ReportLevel.summary:
                goto case;
            case ReportLevel.alive:
                if (status == Mutation.Status.alive) {
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
    }

    override void statStartEvent() {
    }

    override void statEvent(ref Database db) {
    }

    override void statEndEvent() {
    }
}

/// Create a range from `a` that has at most maxlen+3 letters in it.
auto window(T)(T a, size_t maxlen) {
    import std.algorithm : filter, among, joiner;
    import std.range : take, only, chain;

    // dfmt off
    return chain(a.take(maxlen).filter!(a => !a.among('\n')),
                 only(a.length > maxlen ? "..." : null).joiner);
    // dfmt on
}

struct MakeMutationTextResult {
    string original = originalIsCorrupt;
    string mutation;
}

auto makeMutationText(SafeInput file_, const long[2] offs, Mutation.Kind kind) nothrow {
    import dextool.plugin.mutate.backend.generate_mutant : makeMutation;

    MakeMutationTextResult rval;

    try {
        if (offs[0] < file_.read.length) {
            rval.original = file_.read[offs[0] .. offs[1]].toInternal;
        }

        auto mut = makeMutation(kind);
        rval.mutation = mut.mutate(rval.original);
    }
    catch (Exception e) {
        logger.warning(e.msg).collectException;
    }

    return rval;
}
