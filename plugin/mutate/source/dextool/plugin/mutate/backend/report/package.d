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
    import dextool.plugin.mutate.backend.report.compiler;
    import dextool.plugin.mutate.backend.report.csv;
    import dextool.plugin.mutate.backend.report.json;
    import dextool.plugin.mutate.backend.report.markdown;
    import dextool.plugin.mutate.backend.report.plain;

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
            listeners = [new ReportJson(kinds, conf, fio)];
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
