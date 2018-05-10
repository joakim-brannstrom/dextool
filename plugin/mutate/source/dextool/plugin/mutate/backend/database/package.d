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

import dextool.type : AbsolutePath, Path;
import dextool.plugin.mutate.backend.type;

import dextool.plugin.mutate.backend.database.schema;
public import dextool.plugin.mutate.backend.database.type;

/** Wrapper for a sqlite3 database that provide a uniform, easy-to-use
 * interface for the mutation testing plugin.
 */
struct Database {
    import std.conv : to;
    import std.exception : collectException;
    import std.typecons : Nullable;
    import dextool.plugin.mutate.backend.type : MutationPoint, Mutation,
        Checksum;
    import dextool.plugin.mutate.type : MutationOrder;
    import dextool.plugin.mutate.backend.database.standalone : SDatabase = Database;

    SDatabase db;
    alias db this;

    private MutationOrder mut_order;

    static auto make(AbsolutePath db, MutationOrder mut_order) @safe {
        return Database(SDatabase.make(db), mut_order);
    }

    // Not movable. The database should only be passed around as a reference,
    // if at all.
    @disable this(this);

    Nullable!Checksum getFileChecksum(const Path p) @trusted {
        import dextool.plugin.mutate.backend.utility : checksum;

        auto stmt = db.prepare("SELECT checksum0,checksum1 FROM files WHERE path=:path");
        stmt.bind(":path", cast(string) p);
        auto res = stmt.execute;

        typeof(return) rval;
        if (!res.empty) {
            rval = checksum(res.front.peek!long(0), res.front.peek!long(1));
        }

        return rval;
    }

    /** Get the next mutation point + 1 mutant for it that has status unknown.
     *
     * TODO to run many instances in parallel the mutation should be locked.
     * TODO remove nothrow or add a retry-loop
     *
     * The chosen point is randomised.
     *
     * Params:
     *  kind = kind of mutation to retrieve.
     */
    NextMutationEntry nextMutation(const(Mutation.Kind)[] kinds) nothrow @trusted {
        import std.algorithm : map;
        import std.exception : collectException;
        import std.format : format;
        import dextool.plugin.mutate.backend.type;
        import dextool.type : FileName;

        typeof(return) rval;

        auto order = mut_order == MutationOrder.random ? "ORDER BY RANDOM()" : "";

        try {
            auto prep_str = format("SELECT
                                   mutation.id,
                                   mutation.kind,
                                   mutation.time,
                                   mutation_point.offset_begin,
                                   mutation_point.offset_end,
                                   mutation_point.line,
                                   mutation_point.column,
                                   files.path,
                                   files.lang
                                   FROM mutation,mutation_point,files
                                   WHERE
                                   mutation.status == 0 AND
                                   mutation.mp_id == mutation_point.id AND
                                   mutation_point.file_id == files.id AND
                                   mutation.kind IN (%(%s,%)) %s LIMIT 1",
                    kinds.map!(a => cast(int) a), order);
            auto stmt = db.prepare(prep_str);
            // TODO this should work. why doesn't it?
            //stmt.bind(":kinds", format("%(%s,%)", kinds.map!(a => cast(int) a)));
            auto res = stmt.execute;
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
        } catch (Exception e) {
            rval.st = NextMutationEntry.Status.queryError;
            collectException(logger.warning(e.msg));
        }

        return rval;
    }

    void iterateMutants(const Mutation.Kind[] kinds, void delegate(const ref IterateMutantRow) dg) nothrow @trusted {
        import std.algorithm : map;
        import std.format : format;
        import dextool.plugin.mutate.backend.utility : checksum;

        immutable all_mutants = "SELECT
            mutation.id,
            mutation.status,
            mutation.kind,
            mutation.time,
            mutation_point.offset_begin,
            mutation_point.offset_end,
            mutation_point.line,
            mutation_point.column,
            files.path,
            files.checksum0,
            files.checksum1,
            files.lang
            FROM mutation,mutation_point,files
            WHERE
            mutation.kind IN (%(%s,%)) AND
            mutation.mp_id == mutation_point.id AND
            mutation_point.file_id == files.id
            ORDER BY mutation.status";

        try {
            auto res = db.prepare(format(all_mutants, kinds.map!(a => cast(int) a))).execute;
            foreach (ref r; res) {
                IterateMutantRow d;
                d.id = MutationId(r.peek!long(0));
                d.mutation = Mutation(r.peek!int(2).to!(Mutation.Kind),
                        r.peek!int(1).to!(Mutation.Status));
                auto offset = Offset(r.peek!uint(4), r.peek!uint(5));
                d.mutationPoint = MutationPoint(offset, null);
                d.file = r.peek!string(8);
                d.fileChecksum = checksum(r.peek!long(9), r.peek!long(10));
                d.sloc = SourceLoc(r.peek!uint(6), r.peek!uint(7));
                d.lang = r.peek!long(11).to!Language;

                d.testCases = db.getTestCases(d.id);

                dg(d);
            }
        } catch (Exception e) {
            logger.error(e.msg).collectException;
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
    TestCase[] testCases;
    Language lang;
}
