/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file contains a sqlite3 wrapper that is responsible for providing *nice*, easy to use functions for accessing the data in the database.

This module may have dependencies on many internal mutation modules.
*/
module dextool.plugin.mutate.backend.database;

import core.time : Duration, dur;
import logger = std.experimental.logger;
import std.algorithm : map;
import std.datetime : SysTime;
import std.exception : collectException;
import std.format : format;

public import miniorm : toSqliteDateTime, fromSqLiteDateTime, spinSql;

import dextool.type : AbsolutePath, Path;
import dextool.plugin.mutate.backend.type;

import dextool.plugin.mutate.backend.database.schema;
import dextool.plugin.mutate.type : MutationOrder;
public import dextool.plugin.mutate.backend.database.standalone;
public import dextool.plugin.mutate.backend.database.type;

// feels good constant. If it takes more than 5 minutes to open the database
// something is wrong...
immutable dbOpenTimeout = 5.dur!"minutes";

/** Wrapper for a sqlite3 database that provide a uniform, easy-to-use
 * interface for the mutation testing plugin.
 */
struct Database {
    import std.conv : to;
    import std.datetime : SysTime;
    import std.exception : collectException;
    import std.typecons : Nullable;
    import dextool.plugin.mutate.backend.database.standalone : SDatabase = Database;
    import dextool.plugin.mutate.backend.type : MutationPoint, Mutation, Checksum;

    SDatabase db;
    alias db this;

    static auto make(AbsolutePath db) @safe {
        return Database(SDatabase.make(db));
    }

    static auto make() @trusted {
        return Database(SDatabase.make());
    }

    /** Get the next mutation from the worklist to test by the highest
     * priority.
     *
     * The chosen point is randomised.
     *
     * Params:
     *  kind = kind of mutation to retrieve.
     */
    NextMutationEntry nextMutation(const uint maxParallel) @trusted {
        import dextool.plugin.mutate.backend.type;

        typeof(return) rval;

        static immutable sql = "SELECT * FROM
            (SELECT
            t3.id,
            t0.kind,
            t3.compile_time_ms,
            t3.test_time_ms,
            t1.offset_begin,
            t1.offset_end,
            t1.line,
            t1.column,
            t2.path,
            t2.lang
            FROM " ~ mutationTable ~ " t0," ~ mutationPointTable ~ " t1," ~ filesTable
            ~ " t2," ~ mutationStatusTable ~ " t3," ~ mutantWorklistTable ~ " t4
            WHERE
            t0.st_id = t3.id AND
            t3.id = t4.id AND
            t0.mp_id == t1.id AND
            t1.file_id == t2.id
            ORDER BY t4.prio DESC LIMIT :parallel)
            ORDER BY RANDOM() LIMIT 1";
        auto stmt = db.db.prepare(sql);
        stmt.get.bind(":parallel", maxParallel);
        auto res = stmt.get.execute;
        if (res.empty) {
            rval.st = NextMutationEntry.Status.done;
            return rval;
        }

        auto v = res.front;

        auto mp = MutationPoint(Offset(v.peek!uint(4), v.peek!uint(5)));
        mp.mutations = [Mutation(v.peek!long(1).to!(Mutation.Kind))];
        auto pkey = MutationStatusId(v.peek!long(0));
        auto file = Path(v.peek!string(8));
        auto sloc = SourceLoc(v.peek!uint(6), v.peek!uint(7));
        auto lang = v.peek!long(9).to!Language;

        rval.entry = MutationEntry(pkey, file, sloc, mp,
                MutantTimeProfile(v.peek!long(2).dur!"msecs", v.peek!long(3).dur!"msecs"), lang);

        return rval;
    }

    void iterateMutantStatus(scope void delegate(const Mutation.Status, const SysTime added) dg) @trusted {
        static immutable sql = "SELECT t1.status,t1.added_ts FROM "
            ~ mutationTable ~ " t0, " ~ mutationStatusTable ~ " t1
           WHERE t0.st_id = t1.id ORDER BY t1.added_ts";
        auto stmt = db.db.prepare(sql);
        try {
            foreach (ref r; stmt.get.execute) {
                dg(r.peek!int(0).to!(Mutation.Status), r.peek!string(1).fromSqLiteDateTime);
            }
        } catch (Exception e) {
            logger.error(e.msg).collectException;
        }
    }

    void iterateMutants(scope void delegate(const ref IterateMutantRow) dg) @trusted {
        import dextool.plugin.mutate.backend.utility : checksum;

        immutable all_mutants = format("SELECT
            t0.st_id,
            t3.status,
            t0.kind,
            t1.offset_begin,
            t1.offset_end,
            t1.line,
            t1.column,
            t1.line_end,
            t1.column_end,
            t2.path,
            t2.checksum,
            t2.lang,
            t4.nomut
            FROM %s t0,%s t1,%s t2, %s t3, %s t4
            WHERE
            t0.st_id = t3.id AND
            t0.mp_id = t1.id AND
            t1.file_id = t2.id AND
            t0.id = t4.mut_id
            ORDER BY t3.status", mutationTable, mutationPointTable, filesTable,
                mutationStatusTable, srcMetadataTable);

        try {
            auto stmt = db.db.prepare(all_mutants);
            foreach (ref r; stmt.get.execute) {
                IterateMutantRow d;
                d.id = MutationStatusId(r.peek!long(0));
                d.mutation = Mutation(r.peek!int(2).to!(Mutation.Kind),
                        r.peek!int(1).to!(Mutation.Status));
                auto offset = Offset(r.peek!uint(3), r.peek!uint(4));
                d.mutationPoint = MutationPoint(offset, null);
                d.file = r.peek!string(9).Path;
                d.fileChecksum = checksum(r.peek!long(10));
                d.sloc = SourceLoc(r.peek!uint(5), r.peek!uint(6));
                d.slocEnd = SourceLoc(r.peek!uint(7), r.peek!uint(8));
                d.lang = r.peek!long(11).to!Language;

                if (r.peek!long(12) != 0) {
                    d.attrs = MutantMetaData(d.id, MutantAttr(NoMut.init));
                }
                dg(d);
            }
        } catch (Exception e) {
            logger.error(e.msg).collectException;
        }
    }

    void iterateMutants(void delegate(const ref IterateMutantRow2) dg) @trusted {
        static immutable sql = "SELECT
            t3.id,
            t0.kind,
            t3.status,
            t3.exit_code,
            t3.prio,
            t2.path,
            t1.line,
            t1.column,
            t3.update_ts,
            (SELECT count(*) FROM " ~ killedTestCaseTable ~ " WHERE t3.id=st_id) as vc_cnt,
            t4.nomut
            FROM " ~ mutationTable ~ " t0," ~ mutationPointTable ~ " t1," ~ filesTable
            ~ " t2, " ~ mutationStatusTable ~ " t3, " ~ srcMetadataTable ~ " t4
            WHERE
            t0.st_id = t3.id AND
            t0.mp_id = t1.id AND
            t1.file_id = t2.id AND
            t0.id = t4.mut_id
            GROUP BY t3.id
            ORDER BY t2.path,t1.line,t3.id";

        try {
            auto stmt = db.db.prepare(sql);
            foreach (ref r; stmt.get.execute) {
                IterateMutantRow2 d;
                d.stId = MutationStatusId(r.peek!long(0));
                d.mutant = Mutation(r.peek!int(1).to!(Mutation.Kind),
                        r.peek!int(2).to!(Mutation.Status));
                d.exitStatus = r.peek!int(3).ExitStatus;
                d.prio = r.peek!long(4).MutantPrio;
                d.file = r.peek!string(5).Path;
                d.sloc = SourceLoc(r.peek!uint(6), r.peek!uint(7));
                d.tested = r.peek!string(8).fromSqLiteDateTime;
                d.killedByTestCases = r.peek!long(9);

                if (r.peek!long(10) != 0) {
                    d.attrs = MutantMetaData(d.stId, MutantAttr(NoMut.init));
                }

                dg(d);
            }
        } catch (Exception e) {
            logger.error(e.msg).collectException;
        }
    }

    FileRow[] getDetailedFiles() @trusted {
        import std.array : appender;
        import dextool.plugin.mutate.backend.utility : checksum;

        static immutable files_q = "SELECT t0.path, t0.checksum, t0.lang, t0.id FROM "
            ~ filesTable ~ " t0";
        auto app = appender!(FileRow[])();
        auto stmt = db.db.prepare(files_q);
        foreach (ref r; stmt.get.execute) {
            auto fr = FileRow(r.peek!string(0).Path,
                    checksum(r.peek!long(1)), r.peek!Language(2), r.peek!long(3).FileId);
            app.put(fr);
        }

        return app.data;
    }

    /** Iterate over the mutants in a specific file.
     *
     * Mutants are guaranteed to be ordered by their starting offset in the
     * file.
     *
     * Params:
     *  file = the file to retrieve mutants from
     *  dg = callback for reach row
     */
    void iterateFileMutants(Path file, scope void delegate(ref const FileMutantRow) dg) @trusted {
        import std.algorithm : map;

        // TODO: remove the dummy value zero. it is just there to avoid having
        // to update all the peeks.
        static immutable sql = "SELECT
            0,
            t3.id,
            t0.kind,
            t3.status,
            t1.offset_begin,
            t1.offset_end,
            t1.line,
            t1.column,
            t1.line_end,
            t1.column_end,
            t2.lang
            FROM " ~ mutationTable ~ " t0, " ~ mutationPointTable ~ " t1, "
            ~ filesTable ~ " t2, " ~ mutationStatusTable ~ " t3
            WHERE
            t0.st_id = t3.id AND
            t0.mp_id = t1.id AND
            t1.file_id = t2.id AND
            t2.path = :path
            GROUP BY t3.id
            ORDER BY t1.offset_begin";

        auto stmt = db.db.prepare(sql);
        stmt.get.bind(":path", cast(string) file);
        foreach (ref r; stmt.get.execute) {
            FileMutantRow fr;
            fr.stId = MutationStatusId(r.peek!long(1));
            fr.mutation = Mutation(r.peek!int(2).to!(Mutation.Kind),
                    r.peek!int(3).to!(Mutation.Status));
            auto offset = Offset(r.peek!uint(4), r.peek!uint(5));
            fr.mutationPoint = MutationPoint(offset, null);
            fr.sloc = SourceLoc(r.peek!uint(6), r.peek!uint(7));
            fr.slocEnd = SourceLoc(r.peek!uint(8), r.peek!uint(9));
            fr.lang = r.peek!int(10).to!Language;

            dg(fr);
        }
    }
}

struct IterateMutantRow {
    MutationStatusId id;
    Mutation mutation;
    MutationPoint mutationPoint;
    Path file;
    Checksum fileChecksum;
    SourceLoc sloc;
    SourceLoc slocEnd;
    Language lang;
    MutantMetaData attrs;
}

struct IterateMutantRow2 {
    MutationStatusId stId;
    Mutation mutant;
    ExitStatus exitStatus;
    Path file;
    SourceLoc sloc;
    MutantPrio prio;
    SysTime tested;
    long killedByTestCases;
    MutantMetaData attrs;
}

struct FileRow {
    Path file;
    Checksum fileChecksum;
    Language lang;
    FileId id;
}

struct FileMutantRow {
    MutationStatusId stId;
    Mutation mutation;
    MutationPoint mutationPoint;
    SourceLoc sloc;
    SourceLoc slocEnd;
    Language lang;
}
