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
import dextool.plugin.mutate.backend.type : Mutation;

ExitStatusType runReport(ref Database db, const MutationKind kind) @safe nothrow {
    import std.stdio : write;
    import dextool.plugin.mutate.backend.utility;

    import d2sqlite3 : Row;

    const auto kinds = kind.toInternal;

    try {
        auto genrep = ReportGenerator.make(kind);
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
    import std.conv : to;
    import std.format : format;
    import d2sqlite3 : Row;
    import dextool.plugin.mutate.backend.utility;

    static immutable col_w = 10;

    const Mutation.Kind[] kinds;

    Report!(SimpleWriter) markdown;
    Report!(SimpleWriter) markdown_loc;
    Report!(SimpleWriter) markdown_sum;

    static auto make(MutationKind kind) {
        return ReportGenerator(kind.toInternal);
    }

    void mutationKindEvent(MutationKind kind_) {
        markdown = Report!(SimpleWriter)(delegate(const(char)[] s) {
            import std.stdio : write;

            write(s);
        });

        markdown = markdown.heading("Mutation Type %s", kind_);
    }

    void locationStartEvent() {
        markdown_loc = markdown.heading("Locations");
        markdown_loc.beginSyntaxBlock;
        markdown_loc.writeln("%-*s %-*s %-*s %s", col_w, "ID", col_w, "Status",
                col_w, "Kind", "Location");
    }

    // trusted: trusting that d2sqlite3 and sqlite3 is memory safe.
    void locationEvent(ref Row r) @trusted {
        try {
            auto status = r.peek!int(1).to!(Mutation.Status);
            auto kind = r.peek!int(2).to!(Mutation.Kind);
            auto msg = format("%-*s %-*s %-*s %s %s:%s", col_w, r.peek!long(0),
                    col_w, status, col_w, kind, r.peek!string(8),
                    r.peek!long(6), r.peek!long(7));
            if (status == Mutation.Status.alive) {
                markdown.writeln(msg);
            } else {
                markdown.trace(msg);
            }

        }
        catch (Exception e) {
            logger.trace(e.msg).collectException;
        }
    }

    void locationEndEvent() {
        markdown_loc.endSyntaxBlock;
        markdown_loc.popHeading;
    }

    void statStartEvent() {
        markdown_sum = markdown.heading("Summary");
    }

    void statEvent(ref Database db) {
        reportStatistics(db, kinds, markdown_sum);
    }

    void statEndEvent() {
        markdown_sum.popHeading;
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
            item.writeln("Predicted time until mutation testing is done: %s (%s)",
                    predicted, Clock.currTime + predicted);
        if (!untested.isNull && untested.count > 0)
            item.writeln("Untested: %s", untested.count);
        if (!alive.isNull)
            item.writeln("%-*s %-*s (%s)", align_, "Alive:", align_, alive.count, alive.time);
        if (!killed.isNull)
            item.writeln("%-*s %-*s (%s)", align_, "Killed:", align_, killed.count, killed.time);
        if (!timeout.isNull)
            item.writeln("%-*s %-*s (%s)", align_, "Timeout:", align_,
                    timeout.count, timeout.time);
        item.writeln("%-*s %-*s (%s)", align_, "Total:", align_, total_cnt, total_time);
        if (total_cnt > 0)
            item.writeln("%-*s %-*s", align_, "Score:", align_,
                    cast(double) killed_cnt / cast(double) total_cnt);
        if (!killed_by_compiler.isNull)
            item.trace("%-*s %-*s (%s)", align_, "Killed by compiler:", align_,
                    killed_by_compiler.count, killed_by_compiler.time);
    }
    catch (Exception e) {
        logger.error(e.msg).collectException;
    }
}

alias SimpleWriter = void delegate(const(char)[]) @safe;

struct Report(Writer) {
    import std.ascii : newline;
    import std.format : formattedWrite, format;
    import std.range : put;

    private int curr_head;
    private Writer w;

    private this(int heading, Writer w) {
        this.curr_head = heading;
        this.w = w;
    }

    this(Writer w) {
        this.w = w;
    }

    auto heading(ARGS...)(auto ref ARGS args) {
        import std.algorithm : copy;
        import std.range : repeat, take;

        repeat('#').take(curr_head + 1).copy(w);
        put(w, " ");
        formattedWrite(w, args);

        // two newlines because some markdown parsers do not correctly identify a heading if it isn't separated
        put(w, newline);
        put(w, newline);
        return (typeof(this)(curr_head + 1, w));
    }

    auto popHeading() {
        if (curr_head != 0)
            put(w, newline);
        return typeof(this)(curr_head - 1, w);
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
        formattedWrite(w, args);
        return this;
    }

    auto writeln(ARGS...)(auto ref ARGS args) {
        this.write(args), put(w, newline);
        return this;
    }

    auto trace(ARGS...)(auto ref ARGS args) {
        logger.tracef(args);
        return this;
    }
}
