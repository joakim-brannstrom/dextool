/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.compiler;

import logger = std.experimental.logger;
import std.exception : collectException;
import std.path : buildPath;

import dextool.type;

import dextool.plugin.mutate.backend.database : Database, IterateMutantRow;
import dextool.plugin.mutate.backend.generate_mutant : MakeMutationTextResult, makeMutationText;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.report.type : SimpleWriter, ReportEvent;
import dextool.plugin.mutate.backend.report.utility : window, windowSize;
import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.type : MutationKind, ReportLevel;

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
        compiler = CompilerConsole!SimpleWriter(delegate(const(char)[] s) @trusted {
            import std.stdio : stderr, write;

            stderr.write(s);
        });
    }

    override void locationStartEvent(ref Database db) {
    }

    override void locationEvent(ref Database db, const ref IterateMutantRow r) @trusted {
        import dextool.plugin.mutate.backend.generate_mutant : makeMutation;

        void report() {
            AbsolutePath abs_path;
            MakeMutationTextResult mut_txt;
            try {
                abs_path = AbsolutePath(buildPath(fio.getOutputDir, r.file.Path));
                mut_txt = makeMutationText(fio.makeInput(abs_path),
                        r.mutationPoint.offset, r.mutation.kind, r.lang);
            } catch (Exception e) {
                logger.warning(e.msg);
            }

            // dfmt off
            auto b = compiler.build
                .file(abs_path)
                .start(r.sloc)
                .end(r.slocEnd)
                .begin("%s: replace '%s' with '%s'", r.mutation.kind.toUser,
                       window(mut_txt.original, windowSize),
                       window(mut_txt.mutation, windowSize))
                .note("status:%s id:%s", r.mutation.status, r.id);

            if (mut_txt.original.length > windowSize)
                b = b.note("replace '%s'", mut_txt.original);
            if (mut_txt.mutation.length > windowSize)
                b = b.note("with '%s'", mut_txt.mutation);

            b.fixit(mut_txt.mutation).end;
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

private:

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
    import dextool.plugin.mutate.backend.type : SourceLoc;

    private {
        Writer w;
        string file_;
        SourceLoc start_;
        SourceLoc end_;
    }

    this(Writer w) {
        this.w = w;
    }

    auto file(string a) {
        file_ = a;
        return this;
    }

    auto start(SourceLoc a) {
        start_ = a;
        return this;
    }

    auto end(SourceLoc a) {
        end_ = a;
        return this;
    }

    auto begin(ARGS...)(auto ref ARGS args) {
        // for now the severity is hard coded to warning because nothing else
        // needs to be supported.
        formattedWrite(w, "%s:%s:%s: warning: ", file_, start_.line, start_.column);
        formattedWrite(w, args);
        put(w, newline);
        return this;
    }

    auto note(ARGS...)(auto ref ARGS args) {
        formattedWrite(w, "%s:%s:%s: note: ", file_, start_.line, start_.column);
        formattedWrite(w, args);
        put(w, newline);
        return this;
    }

    auto fixit(const(char)[] mutation) {
        // Example of a fixit hint from gcc:
        // fix-it:"foo.cpp":{5:12-5:17}:"argc"
        // the second value in the location is bytes (starting from 1) from the
        // start of the line.
        formattedWrite(w, `fix-it:"%s":{%s:%s-%s:%s}:"%s"`, file_, start_.line,
                start_.column, end_.line, end_.column, mutation);
        put(w, newline);
        return this;
    }

    void end() {
    }
}
