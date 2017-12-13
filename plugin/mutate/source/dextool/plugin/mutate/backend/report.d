/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report;

import std.exception : collectException;
import logger = std.experimental.logger;

import dextool.type;

import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.type : MutationKind;

ExitStatusType runReport(ref Database db, const MutationKind kind) @safe nothrow {
    import dextool.plugin.mutate.backend.utility;

    auto alive = db.aliveMutants(kind.toInternal);
    auto killed = db.killedMutants(kind.toInternal);
    auto timeout = db.timeoutMutants(kind.toInternal);
    auto untested = db.unknownMutants(kind.toInternal);

    try {
        logger.infof("Mutation statistics (%s)", kind);
        logger.info(!alive.isNull && !killed.isNull && !timeout.isNull,
                "Total time running mutation testing (compilation + test): ",
                alive.time + killed.time + timeout.time);
        logger.infof(!timeout.isNull, "Untested: %s", untested.count);
        logger.infof(!alive.isNull, "Alive: %s (%s)", alive.count, alive.time);
        logger.infof(!killed.isNull, "Killed: %s (%s)", killed.count, killed.time);
        logger.infof(!timeout.isNull, "Timeout: %s (%s)", timeout.count, timeout.time);
        logger.info(!alive.isNull && !killed.isNull, "Score: ",
                (cast(double) alive.count) / (cast(double)(alive.count + killed.count)));
    }
    catch (Exception e) {
        logger.error(e.msg).collectException;
    }

    return ExitStatusType.Ok;
}

private:
