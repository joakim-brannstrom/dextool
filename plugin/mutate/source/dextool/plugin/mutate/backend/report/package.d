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

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.diff_parser : Diff, diffFromStdin;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.utility : getProfileResult, Profile;
import dextool.plugin.mutate.config : ConfigReport;
import dextool.plugin.mutate.type : MutationKind, ReportKind;

ExitStatusType runReport(const AbsolutePath dbPath, const MutationKind[] kind,
        const ConfigReport conf, FilesysIO fio) @trusted nothrow {

    ExitStatusType helper(ref Database db) {
        Diff diff;
        if (conf.unifiedDiff) {
            diff = diffFromStdin;
        }

        final switch (conf.reportKind) with (ReportKind) {
        case plain:
            import dextool.plugin.mutate.backend.report.plain : report;

            report(db, kind, conf, fio);
            break;
        case compiler:
            import dextool.plugin.mutate.backend.report.compiler : report;

            report(db, kind, conf, fio);
            break;
        case json:
            import dextool.plugin.mutate.backend.report.json : report;

            report(db, kind, conf, fio, diff);
            break;
        case html:
            import dextool.plugin.mutate.backend.report.html : report;

            report(db, kind, conf, fio, diff);
            break;
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

    try {
        auto db = Database.make(dbPath);
        return helper(db);
    } catch (Exception e) {
        logger.error(e.msg).collectException;
    }

    return ExitStatusType.Errors;
}
