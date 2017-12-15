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
    import core.time : dur;
    import std.algorithm : map, filter, sum;
    import std.range : only;
    import std.datetime : Clock;
    import dextool.plugin.mutate.backend.utility;

    auto kinds = kind.toInternal;

    auto alive = db.aliveMutants(kinds);
    auto killed = db.killedMutants(kinds);
    auto timeout = db.timeoutMutants(kinds);
    auto untested = db.unknownMutants(kinds);
    auto killed_by_compiler = db.killedByCompilerMutants(kind.toInternal);

    try {
        const auto total_time = only(alive, killed, timeout).filter!(a => !a.isNull)
            .map!(a => a.time.total!"msecs").sum.dur!"msecs";
        const auto total_cnt = only(alive, killed, timeout).filter!(a => !a.isNull)
            .map!(a => a.count).sum;
        const auto untested_cnt = untested.isNull ? 0 : untested.count;
        const auto predicted = total_cnt > 0 ? (untested_cnt * (total_time / total_cnt))
            : 0.dur!"msecs";

        logger.infof("Mutation statistics (%s)", kind);
        logger.info("Total time running mutation testing (compilation + test): ", total_time);
        logger.infof(untested_cnt > 0 && predicted > 0.dur!"msecs",
                "Predicted time until mutation testing is done: %s (%s)",
                predicted, Clock.currTime + predicted);
        logger.infof(!untested.isNull && untested.count > 0, "Untested: %s", untested.count);
        logger.infof(!alive.isNull, "Alive: %s (%s)", alive.count, alive.time);
        logger.infof(!killed.isNull, "Killed: %s (%s)", killed.count, killed.time);
        logger.infof(!timeout.isNull, "Timeout: %s (%s)", timeout.count, timeout.time);
        logger.tracef(!killed_by_compiler.isNull, "Killed by compiler: %s (%s)",
                killed_by_compiler.count, killed_by_compiler.time);
        logger.info(total_cnt > 0, "Score: ", (cast(double)(killed.isNull ? 0
                : killed.count) / cast(double) total_cnt));
    }
    catch (Exception e) {
        logger.error(e.msg).collectException;
    }

    import d2sqlite3 : Row;

    // trusted: trustin gthat d2sqlite3 and sqlite3 is memory safe.
    void locationPrinter(ref Row r) @trusted nothrow {
        import std.conv : to;
        import std.format : format;

        try {
            auto status = r.peek!int(1).to!(Mutation.Status);
            auto msg = format("%s %s %s %s:%s:%s", r.peek!long(0), status,
                    r.peek!int(2).to!(Mutation.Kind), r.peek!string(8),
                    r.peek!long(6), r.peek!long(7));
            if (status == Mutation.Status.killedByCompiler)
                logger.trace(msg);
            else
                logger.info(msg);

        }
        catch (Exception e) {
            logger.trace(e.msg).collectException;
        }
    }

    logger.info("ID Status Kind Location").collectException;
    db.iterateMutants(kinds, &locationPrinter);

    return ExitStatusType.Ok;
}
