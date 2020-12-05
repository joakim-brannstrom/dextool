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

import logger = std.experimental.logger;
import std.ascii : newline;
import std.exception : collectException;

import dextool.type;

import dextool.plugin.mutate.backend.database : Database, IterateMutantRow;
import dextool.plugin.mutate.backend.diff_parser : Diff, diffFromStdin;
import dextool.plugin.mutate.backend.generate_mutant : MakeMutationTextResult, makeMutationText;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.report.type : SimpleWriter, ReportEvent,
    FileReport, FilesReporter;
import dextool.plugin.mutate.backend.report.utility : window, windowSize;
import dextool.plugin.mutate.backend.type : Mutation, Offset;
import dextool.plugin.mutate.backend.utility : getProfileResult, Profile;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind, ReportKind, ReportLevel, ReportSection;

ExitStatusType runReport(ref Database db, const MutationKind[] kind,
        const ConfigReport conf, FilesysIO fio) @trusted nothrow {
    Diff diff;
    try {
        if (conf.unifiedDiff)
            diff = diffFromStdin;
    } catch (Exception e) {
        logger.warning(e.msg).collectException;
    }

    try {
        auto genrep = ReportGenerator.make(db, kind, conf, fio);
        runAllMutantReporter(db, kind, genrep);

        auto fp = makeFilesReporter(db, conf, kind, fio, diff);
        if (fp !is null)
            runFilesReporter(db, fp, kind);
    } catch (Exception e) {
        debug logger.trace(e).collectException;
        logger.error(e.msg).collectException;
        return ExitStatusType.Errors;
    }

    if (conf.profile)
        try {
            import std.stdio : writeln;

            writeln(getProfileResult.toString);
        } catch (Exception e) {
            logger.warning("Unable to print the profile data: ", e.msg).collectException;
        }

    return ExitStatusType.Ok;
}

@safe:
private:

void runAllMutantReporter(ref Database db, const(MutationKind)[] kind, ref ReportGenerator genrep) {
    import dextool.plugin.mutate.backend.utility;

    const kinds = dextool.plugin.mutate.backend.utility.toInternal(kind);

    // TODO remove this parameter. seems to be unnecessary.
    genrep.mutationKindEvent(kind);

    genrep.locationStartEvent(db);
    {
        auto profile = Profile("iterate mutants for report");
        db.iterateMutants(kinds, &genrep.locationEvent);
    }

    auto profile = Profile("post process report");
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
        auto profile = Profile("generate report for " ~ f.file);
        auto fp = fps.getFileReportEvent(db, f);
        db.iterateFileMutants(kinds, f.file, &fp.fileMutantEvent);
        fp.endFileEvent(db);
    }

    auto profile = Profile("post process report");
    fps.postProcessEvent(db);
    fps.endEvent(db);
}

FilesReporter makeFilesReporter(ref Database db, const ConfigReport conf,
        const(MutationKind)[] kind, FilesysIO fio, ref Diff diff) {
    import dextool.plugin.mutate.backend.report.html;
    import dextool.plugin.mutate.backend.report.json;
    import dextool.plugin.mutate.backend.utility;

    const auto kinds = dextool.plugin.mutate.backend.utility.toInternal(kind);

    final switch (conf.reportKind) {
    case ReportKind.plain:
        goto case;
    case ReportKind.compiler:
        return null;
    case ReportKind.json:
        return new ReportJson(kinds, conf, fio, diff);
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
    import dextool.plugin.mutate.backend.report.html;
    import dextool.plugin.mutate.backend.report.plain;

    Database db;
    ReportEvent[] listeners;
    FilesReporter fileReporter;

    static auto make(ref Database db, const MutationKind[] kind,
            const ConfigReport conf, FilesysIO fio) @system {
        import dextool.plugin.mutate.backend.utility;

        auto kinds = dextool.plugin.mutate.backend.utility.toInternal(kind);
        ReportEvent[] listeners;

        final switch (conf.reportKind) {
        case ReportKind.plain:
            listeners = [new ReportPlain(kinds, conf, fio)];
            break;
        case ReportKind.compiler:
            listeners = [new ReportCompiler(kinds, conf.reportLevel, fio)];
            break;
        case ReportKind.json:
            listeners = null;
            break;
        case ReportKind.html:
            listeners = null;
            break;
        }

        return ReportGenerator(db, listeners);
    }

    void mutationKindEvent(const MutationKind[] kind_) {
        listeners.each!(a => a.mutationKindEvent(kind_));
    }

    void locationStartEvent(ref Database db) {
        listeners.each!(a => a.locationStartEvent(db));
    }

    // trusted: trusting that d2sqlite3 and sqlite3 is memory safe.
    void locationEvent(const ref IterateMutantRow r) @trusted {
        listeners.each!(a => a.locationEvent(db, r));
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
