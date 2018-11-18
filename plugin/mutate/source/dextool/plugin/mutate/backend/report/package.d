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
import dextool.plugin.mutate.type : MutationKind, ReportKind, ReportLevel, ReportSection;
import dextool.plugin.mutate.backend.type : Mutation, Offset;

import dextool.plugin.mutate.backend.diff_parser : Diff;
import dextool.plugin.mutate.backend.report.type : SimpleWriter, ReportEvent,
    FileReport, FilesReporter;
import dextool.plugin.mutate.backend.report.utility : MakeMutationTextResult,
    window, windowSize, makeMutationText;
import dextool.plugin.mutate.config : ConfigReport;

ExitStatusType runReport(ref Database db, const MutationKind[] kind,
        const ConfigReport conf, FilesysIO fio) @safe nothrow {
    Diff diff;
    try {
        if (conf.unifiedDiff)
            diff = fromStdin;
    } catch (Exception e) {
        logger.warning(e.msg).collectException;
    }

    try {
        auto genrep = ReportGenerator.make(kind, conf, fio);
        runAllMutantReporter(db, kind, genrep);

        auto fp = makeFilesReporter(db, conf, kind, fio, diff);
        if (fp !is null)
            runFilesReporter(db, fp, kind);
    } catch (Exception e) {
        logger.error(e.msg).collectException;
        return ExitStatusType.Errors;
    }

    return ExitStatusType.Ok;
}

@safe:
private:

void runAllMutantReporter(ref Database db, const(MutationKind)[] kind, ref ReportGenerator genrep) {
    import dextool.plugin.mutate.backend.utility;

    const auto kinds = dextool.plugin.mutate.backend.utility.toInternal(kind);

    // TODO remove this parameter. seems to be unnecessary.
    genrep.mutationKindEvent(kind is null ? [MutationKind.any] : kind);

    genrep.locationStartEvent;
    db.iterateMutants(kinds, &genrep.locationEvent);
    genrep.locationEndEvent;

    genrep.locationStatEvent;

    genrep.statEvent(db);
}

void runFilesReporter(ref Database db, FilesReporter fps, const(MutationKind)[] kind) {
    assert(fps !is null, "report should never be null");

    import dextool.plugin.mutate.backend.utility;
    import dextool.plugin.mutate.backend.database : FileMutantRow;

    const auto kinds = dextool.plugin.mutate.backend.utility.toInternal(kind);

    fps.mutationKindEvent(kind);

    foreach (f; db.getDetailedFiles) {
        auto fp = fps.getFileReportEvent(db, f);
        db.iterateFileMutants(kinds, f.file, &fp.fileMutantEvent);
        fp.endFileEvent(db);
    }

    fps.postProcessEvent(db);
    fps.endEvent(db);
}

FilesReporter makeFilesReporter(ref Database db, const ConfigReport conf,
        const(MutationKind)[] kind, FilesysIO fio, ref Diff diff) {
    import dextool.plugin.mutate.backend.report.html;
    import dextool.plugin.mutate.backend.utility;

    const auto kinds = dextool.plugin.mutate.backend.utility.toInternal(kind);

    final switch (conf.reportKind) {
    case ReportKind.plain:
    case ReportKind.markdown:
    case ReportKind.compiler:
    case ReportKind.json:
    case ReportKind.csv:
        return null;
    case ReportKind.html:
        return new ReportHtml(kinds, conf, fio, diff);
    }
}

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
    import dextool.plugin.mutate.backend.report.compiler;
    import dextool.plugin.mutate.backend.report.csv;
    import dextool.plugin.mutate.backend.report.html;
    import dextool.plugin.mutate.backend.report.json;
    import dextool.plugin.mutate.backend.report.markdown;
    import dextool.plugin.mutate.backend.report.plain;

    ReportEvent[] listeners;
    FilesReporter fileReporter;

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
            listeners = [new ReportJson(kinds, conf, fio)];
            break;
        case ReportKind.csv:
            listeners = [new ReportCSV(kinds, conf.reportLevel, fio)];
            break;
        case ReportKind.html:
            listeners = null;
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

Diff fromStdin() @trusted {
    import std.stdio : stdin;
    import dextool.plugin.mutate.backend.diff_parser : UnifiedDiffParser;

    UnifiedDiffParser parser;
    foreach (l; stdin.byLine) {
        debug logger.trace(l);
        parser.process(l);
    }
    return parser.result;
}
