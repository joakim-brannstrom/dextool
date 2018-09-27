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

import dextool.plugin.mutate.backend.database : Database, IterateMutantRow;
import dextool.plugin.mutate.backend.interface_ : FilesysIO, SafeInput;
import dextool.plugin.mutate.type : MutationKind, ReportKind, ReportLevel,
    ReportSection;
import dextool.plugin.mutate.backend.type : Mutation, Offset;

import dextool.plugin.mutate.backend.report.type : SimpleWriter, ReportEvent;
import dextool.plugin.mutate.backend.report.utility : MakeMutationTextResult,
    window, windowSize, makeMutationText;
import dextool.plugin.mutate.config : ConfigReport;

ExitStatusType runReport(ref Database db, const MutationKind[] kind,
        const ConfigReport conf, FilesysIO fio) @safe nothrow {
    import std.stdio : write;
    import dextool.plugin.mutate.backend.utility;

    const auto kinds = dextool.plugin.mutate.backend.utility.toInternal(kind);

    try {
        auto genrep = ReportGenerator.make(kind, conf, fio);
        genrep.mutationKindEvent(kind is null ? [MutationKind.any] : kind);

        genrep.locationStartEvent;
        db.iterateMutants(kinds, &genrep.locationEvent);
        genrep.locationEndEvent;

        genrep.locationStatEvent;

        genrep.statEvent(db);
    } catch (Exception e) {
        logger.error(e.msg).collectException;
    }

    return ExitStatusType.Ok;
}

@safe:
private:

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
    import dextool.plugin.mutate.backend.report.markdown;
    import dextool.plugin.mutate.backend.report.plain;
    import dextool.plugin.mutate.backend.report.csv;

    ReportEvent[] listeners;

    static auto make(const MutationKind[] kind, const ConfigReport conf, FilesysIO fio) {
        import dextool.plugin.mutate.backend.utility;

        auto kinds = dextool.plugin.mutate.backend.utility.toInternal(kind);
        ReportEvent[] listeners;

        final switch (conf.reportKind) {
        case ReportKind.plain:
            listeners = [new ReportPlain(kinds, conf, fio)];
            break;
        case ReportKind.markdown:
            listeners = [new ReportMarkdown(kinds, conf, fio)];
            break;
        case ReportKind.compiler:
            listeners = [new ReportCompiler(kinds, conf.reportLevel, fio)];
            break;
        case ReportKind.json:
            listeners = [new ReportJson(conf.reportLevel, fio)];
            break;
        case ReportKind.csv:
            listeners = [new ReportCSV(kinds, conf.reportLevel, fio)];
            break;
        }

        return ReportGenerator(listeners);
    }

    void mutationKindEvent(const MutationKind[] kind_) {
        listeners.each!(a => a.mutationKindEvent(kind_));
    }

    void locationStartEvent() {
        listeners.each!(a => a.locationStartEvent);
    }

    // trusted: trusting that d2sqlite3 and sqlite3 is memory safe.
    void locationEvent(const ref IterateMutantRow r) @trusted {
        listeners.each!(a => a.locationEvent(r));
    }

    void locationEndEvent() {
        listeners.each!(a => a.locationEndEvent);
    }

    void locationStatEvent() {
        listeners.each!(a => a.locationStatEvent);
    }

    void statEvent(ref Database db) {
        listeners.each!(a => a.statEvent(db));
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

/** Report mutations as gcc would do for compilation warnings with fixit hints.
 *
 * #SPC-report_for_tool_integration
 */
@safe final class ReportCompiler : ReportEvent {
    import std.algorithm : each;
    import std.conv : to;
    import std.format : format;
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

    override void mutationKindEvent(const MutationKind[]) {
        compiler = CompilerConsole!SimpleWriter(delegate(const(char)[] s) @trusted{
            import std.stdio : stderr, write;

            stderr.write(s);
        });
    }

    override void locationStartEvent() {
    }

    override void locationEvent(const ref IterateMutantRow r) @trusted {
        import dextool.plugin.mutate.backend.generate_mutant : makeMutation;

        void report() {
            AbsolutePath abs_path;
            MakeMutationTextResult mut_txt;
            try {
                abs_path = AbsolutePath(FileName(r.file), DirName(fio.getOutputDir));
                mut_txt = makeMutationText(fio.makeInput(abs_path),
                        r.mutationPoint.offset, r.mutation.kind, r.lang);
            } catch (Exception e) {
                logger.warning(e.msg);
            }

            // dfmt off
            auto b = compiler.build
                .file(abs_path)
                .line(r.sloc.line)
                .column(r.sloc.column)
                .begin("%s: replace '%s' with '%s'", r.mutation.kind.toUser,
                       window(mut_txt.original, windowSize),
                       window(mut_txt.mutation, windowSize))
                .note("status:%s id:%s", r.mutation.status, r.id);

            if (mut_txt.original.length > windowSize)
                b = b.note("replace '%s'", mut_txt.original);
            if (mut_txt.mutation.length > windowSize)
                b = b.note("with '%s'", mut_txt.mutation);

            b.fixit(r.mutationPoint.offset.end - r.mutationPoint.offset.begin, mut_txt.mutation)
                .end;
            // dfmt on
        }

        try {
            // summary is the default and according to the specification of the
            // default for tool integration alive mutations shall be printed.
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
        } catch (Exception e) {
            logger.trace(e.msg).collectException;
        }
    }

    override void locationEndEvent() {
    }

    override void locationStatEvent() {
    }

    override void statEvent(ref Database db) {
    }
}

/**
 * Expects locations to be grouped by file.
 *
 * TODO this is ugly. Use a JSON serializer instead.
 */
@safe final class ReportJson : ReportEvent {
    import std.array : array;
    import std.algorithm : map, joiner;
    import std.conv : to;
    import std.format : format;
    import std.json;

    const ReportLevel report_level;
    FilesysIO fio;

    JSONValue report;
    JSONValue current_file;

    Path last_file;

    this(ReportLevel report_level, FilesysIO fio) {
        this.report_level = report_level;
        this.fio = fio;
    }

    override void mutationKindEvent(const MutationKind[] kinds) {
        report = ["types" : kinds.map!(a => a.to!string).array, "files" : []];
    }

    override void locationStartEvent() {
    }

    override void locationEvent(const ref IterateMutantRow r) @trusted {
        bool new_file;

        if (last_file.length == 0) {
            current_file = ["filename" : r.file, "checksum" : format("%x", r.fileChecksum)];
            new_file = true;
        } else if (last_file != r.file) {
            report["files"].array ~= current_file;
            current_file = ["filename" : r.file, "checksum" : format("%x", r.fileChecksum)];
            new_file = true;
        }

        auto appendMutant() {
            JSONValue m = ["id" : r.id.to!long];
            m.object["kind"] = r.mutation.kind.to!string;
            m.object["status"] = r.mutation.status.to!string;
            m.object["line"] = r.sloc.line;
            m.object["column"] = r.sloc.column;
            m.object["begin"] = r.mutationPoint.offset.begin;
            m.object["end"] = r.mutationPoint.offset.end;

            try {
                MakeMutationTextResult mut_txt;
                auto abs_path = AbsolutePath(FileName(r.file), DirName(fio.getOutputDir));
                mut_txt = makeMutationText(fio.makeInput(abs_path),
                        r.mutationPoint.offset, r.mutation.kind, r.lang);
                m.object["value"] = mut_txt.mutation;
            } catch (Exception e) {
                logger.warning(e.msg);
            }
            if (new_file) {
                last_file = r.file;
                current_file.object["mutants"] = JSONValue([m]);
            } else {
                current_file["mutants"].array ~= m;
            }
        }

        final switch (report_level) {
        case ReportLevel.summary:
            break;
        case ReportLevel.alive:
            if (r.mutation.status == Mutation.Status.alive) {
                appendMutant;
            }
            break;
        case ReportLevel.all:
            appendMutant;
            break;
        }
    }

    override void locationEndEvent() @trusted {
        report["files"].array ~= current_file;
    }

    override void locationStatEvent() {
        import std.stdio : writeln;

        writeln(report.toJSON(true));
    }

    override void statEvent(ref Database db) {
    }
}
