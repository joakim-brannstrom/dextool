/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

#SPC-report_as_csv
*/
module dextool.plugin.mutate.backend.report.csv;

import std.exception : collectException;
import logger = std.experimental.logger;

import dextool.type;

import dextool.plugin.mutate.type : MutationKind, ReportKind, ReportLevel;
import dextool.plugin.mutate.backend.database : Database, IterateMutantRow;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.type : Mutation, Offset;

import dextool.plugin.mutate.backend.generate_mutant : MakeMutationTextResult, makeMutationText;
import dextool.plugin.mutate.backend.report.type : SimpleWriter, ReportEvent;
import dextool.plugin.mutate.backend.report.utility : window, windowSize;
import dextool.plugin.mutate.backend.report.analyzers : reportMutationSubtypeStats,
    reportStatistics, Table;

@safe:

/** Report mutations in a format easily imported to Excel like software.
 */
final class ReportCSV : ReportEvent {
    import std.conv : to;
    import std.format : format, FormatSpec;
    import dextool.plugin.mutate.backend.utility;

    const Mutation.Kind[] kinds;
    const ReportLevel report_level;
    FilesysIO fio;

    alias Writer = void function(const(char)[]);
    Writer writer = (const(char)[] s) { import std.stdio : write;

    write(s); };

    this(Mutation.Kind[] kinds, ReportLevel report_level, FilesysIO fio) {
        this.kinds = kinds;
        this.report_level = report_level;
        this.fio = fio;
    }

    override void mutationKindEvent(const MutationKind[] kind_) {
        writeCSV(writer, "ID", "Kind", "Description", "Location", "Comment");
    }

    override void locationStartEvent(ref Database db) {
    }

    override void locationEvent(const ref IterateMutantRow r) @trusted {
        import std.conv : to;

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

            immutable textualDescriptionLen = 255;
            auto desc = format(`'%s' to '%s'`, toField(mut_txt.original,
                    textualDescriptionLen), toField(mut_txt.mutation, textualDescriptionLen));
            auto loc = format("%s:%s:%s", r.file, r.sloc.line, r.sloc.column);
            writer.writeCSV(r.id, r.mutation.kind.toUser, desc, loc, "");
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

/// Write a line as CSV
void writeCSV(Writer, T...)(scope Writer w, auto ref T args) {
    import std.ascii : newline;
    import std.format : formattedWrite;
    import std.range.primitives : put;

    bool first = true;
    foreach (a; args) {
        if (!first)
            put(w, ",");

        static if (__traits(hasMember, a, "isNull")) {
            if (!a.isNull) {
                () @trusted { formattedWrite(w, `"%s"`, a); }();
            }
        } else {
            () @trusted { formattedWrite(w, `"%s"`, a); }();
        }

        first = false;
    }

    put(w, newline);
}

/// Returns: conversion to a valid CSV field.
auto toField(T)(T r, size_t maxlen) {
    import std.algorithm : filter;
    import std.range : take;

    return r.take(maxlen).filter!(a => a != '"');
}
