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
import std.format : format;

public import miniorm : toSqliteDateTime, fromSqLiteDateTime, spinSql;

import dextool.type : AbsolutePath, Path;
import dextool.plugin.mutate.backend.type;

import dextool.plugin.mutate.backend.database.schema;
public import dextool.plugin.mutate.backend.database.type;
public import dextool.plugin.mutate.backend.database.standalone;

/** Wrapper for a sqlite3 database that provide a uniform, easy-to-use
 * interface for the mutation testing plugin.
 */
struct Database {
    import std.conv : to;
    import std.exception : collectException;
    import std.typecons : Nullable;
    import dextool.plugin.mutate.backend.type : MutationPoint, Mutation, Checksum;
    import dextool.plugin.mutate.type : MutationOrder;
    import dextool.plugin.mutate.backend.database.standalone : SDatabase = Database;

    SDatabase db;
    alias db this;

    private MutationOrder mut_order;

    static auto make(AbsolutePath db, MutationOrder mut_order) @safe {
        return Database(SDatabase.make(db), mut_order);
    }

    Nullable!Checksum getFileChecksum(const Path p) @trusted {
        import dextool.plugin.mutate.backend.utility : checksum;

        auto stmt = db.prepare("SELECT checksum0,checksum1 FROM files WHERE path=:path");
        stmt.get.bind(":path", cast(string) p);
        auto res = stmt.get.execute;

        typeof(return) rval;
        if (!res.empty) {
            rval = checksum(res.front.peek!long(0), res.front.peek!long(1));
        }

        return rval;
    }

    /** Get the next mutation point + 1 mutant for it that has status unknown.
     *
     * TODO to run many instances in parallel the mutation should be locked.
     *
     * The chosen point is randomised.
     *
     * Params:
     *  kind = kind of mutation to retrieve.
     */
    NextMutationEntry nextMutation(const(Mutation.Kind)[] kinds) @trusted {
        import std.algorithm : map;
        import std.exception : collectException;
        import dextool.plugin.mutate.backend.type;
        import dextool.type : FileName;

        typeof(return) rval;

        auto order = mut_order == MutationOrder.random ? "ORDER BY RANDOM()" : "";

        immutable sql = format("SELECT
                               t0.id,
                               t0.kind,
                               t3.time,
                               t1.offset_begin,
                               t1.offset_end,
                               t1.line,
                               t1.column,
                               t2.path,
                               t2.lang
                               FROM %s t0,%s t1,%s t2,%s t3
                               WHERE
                               t0.st_id = t3.id AND
                               t3.status == 0 AND
                               t0.mp_id == t1.id AND
                               t1.file_id == t2.id AND
                               t0.kind IN (%(%s,%)) %s LIMIT 1", mutationTable, mutationPointTable,
                filesTable, mutationStatusTable, kinds.map!(a => cast(int) a), order);
        auto stmt = db.prepare(sql);
        auto res = stmt.get.execute;
        if (res.empty) {
            rval.st = NextMutationEntry.Status.done;
            return rval;
        }

        auto v = res.front;

        auto mp = MutationPoint(Offset(v.peek!uint(3), v.peek!uint(4)));
        mp.mutations = [Mutation(v.peek!long(1).to!(Mutation.Kind))];
        auto pkey = MutationId(v.peek!long(0));
        auto file = Path(FileName(v.peek!string(7)));
        auto sloc = SourceLoc(v.peek!uint(5), v.peek!uint(6));
        auto lang = v.peek!long(8).to!Language;

        rval.entry = MutationEntry(pkey, file, sloc, mp, v.peek!long(2).dur!"msecs", lang);

        return rval;
    }

    void iterateMutants(const Mutation.Kind[] kinds, void delegate(const ref IterateMutantRow) dg) @trusted {
        import std.algorithm : map;
        import dextool.plugin.mutate.backend.utility : checksum;

        immutable all_mutants = format("SELECT
            t0.id,
            t3.status,
            t0.kind,
            t3.time,
            t1.offset_begin,
            t1.offset_end,
            t1.line,
            t1.column,
            t1.line_end,
            t1.column_end,
            t2.path,
            t2.checksum0,
            t2.checksum1,
            t2.lang,
            t4.nomut
            FROM %s t0,%s t1,%s t2, %s t3, %s t4
            WHERE
            t0.kind IN (%(%s,%)) AND
            t0.st_id = t3.id AND
            t0.mp_id = t1.id AND
            t1.file_id = t2.id AND
            t0.id = t4.mut_id
            ORDER BY t3.status", mutationTable, mutationPointTable,
                filesTable, mutationStatusTable, srcMetadataTable, kinds.map!(a => cast(int) a));

        try {
            auto stmt = db.prepare(all_mutants);
            foreach (ref r; stmt.get.execute) {
                IterateMutantRow d;
                d.id = MutationId(r.peek!long(0));
                d.mutation = Mutation(r.peek!int(2).to!(Mutation.Kind),
                        r.peek!int(1).to!(Mutation.Status));
                auto offset = Offset(r.peek!uint(4), r.peek!uint(5));
                d.mutationPoint = MutationPoint(offset, null);
                d.file = r.peek!string(10);
                d.fileChecksum = checksum(r.peek!long(11), r.peek!long(12));
                d.sloc = SourceLoc(r.peek!uint(6), r.peek!uint(7));
                d.slocEnd = SourceLoc(r.peek!uint(8), r.peek!uint(9));
                d.lang = r.peek!long(13).to!Language;

                if (r.peek!long(14) != 0)
                    d.attrs = MutantMetaData(d.id, MutantAttr(NoMut.init));
                dg(d);
            }
        } catch (Exception e) {
            logger.error(e.msg).collectException;
        }
    }

    FileRow[] getDetailedFiles() @trusted {
        import std.array : appender;
        import dextool.plugin.mutate.backend.utility : checksum;

        enum files_q = format("SELECT t0.path, t0.checksum0, t0.checksum1, t0.lang, t0.id FROM %s t0",
                    filesTable);
        auto app = appender!(FileRow[])();
        auto stmt = db.prepare(files_q);
        foreach (ref r; stmt.get.execute) {
            auto fr = FileRow(r.peek!string(0).Path, checksum(r.peek!long(1),
                    r.peek!long(2)), r.peek!Language(3), r.peek!long(4).FileId);
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
     *  kinds = the type of mutation operators to have in the report
     *  file = the file to retrieve mutants from
     *  dg = callback for reach row
     */
    void iterateFileMutants(const Mutation.Kind[] kinds, Path file,
            void delegate(ref const FileMutantRow) dg) @trusted {
        import std.algorithm : map;

        immutable all_fmut = format("SELECT
            t0.id,
            t0.kind,
            t3.status,
            t1.offset_begin,
            t1.offset_end,
            t1.line,
            t1.column,
            t1.line_end,
            t1.column_end,
            t2.lang
            FROM %s t0, %s t1, %s t2, %s t3
            WHERE
            t0.kind IN (%(%s,%)) AND
            t0.st_id = t3.id AND
            t0.mp_id = t1.id AND
            t1.file_id = t2.id AND
            t2.path = :path
            ORDER BY t1.offset_begin
            ", mutationTable, mutationPointTable,
                filesTable, mutationStatusTable, kinds.map!(a => cast(int) a));

        auto stmt = db.prepare(all_fmut);
        stmt.get.bind(":path", cast(string) file);
        foreach (ref r; stmt.get.execute) {
            FileMutantRow fr;
            fr.id = MutationId(r.peek!long(0));
            fr.mutation = Mutation(r.peek!int(1).to!(Mutation.Kind),
                    r.peek!int(2).to!(Mutation.Status));
            auto offset = Offset(r.peek!uint(3), r.peek!uint(4));
            fr.mutationPoint = MutationPoint(offset, null);
            fr.sloc = SourceLoc(r.peek!uint(5), r.peek!uint(6));
            fr.slocEnd = SourceLoc(r.peek!uint(7), r.peek!uint(8));
            fr.lang = r.peek!int(9).to!Language;

            dg(fr);
        }
    }
}

struct IterateMutantRow {
    MutationId id;
    Mutation mutation;
    MutationPoint mutationPoint;
    Path file;
    Checksum fileChecksum;
    SourceLoc sloc;
    SourceLoc slocEnd;
    Language lang;
    MutantMetaData attrs;
}

struct FileRow {
    Path file;
    Checksum fileChecksum;
    Language lang;
    FileId id;
}

struct FileMutantRow {
    MutationId id;
    Mutation mutation;
    MutationPoint mutationPoint;
    SourceLoc sloc;
    SourceLoc slocEnd;
    Language lang;
}
