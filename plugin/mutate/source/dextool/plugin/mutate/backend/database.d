/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

# Sqlite3
From the sqlite3 manual $(LINK https://www.sqlite.org/datatype3.html):
Each value stored in an SQLite database (or manipulated by the database
engine) has one of the following storage classes:

NULL. The value is a NULL value.

INTEGER. The value is a signed integer, stored in 1, 2, 3, 4, 6, or 8 bytes
depending on the magnitude of the value.

REAL. The value is a floating point value, stored as an 8-byte IEEE floating
point number.

TEXT. The value is a text string, stored using the database encoding (UTF-8,
UTF-16BE or UTF-16LE).

BLOB. The value is a blob of data, stored exactly as it was input.

A storage class is more general than a datatype. The INTEGER storage class, for
example, includes 6 different integer datatypes of different lengths.  This
makes a difference on disk. But as soon as INTEGER values are read off of disk
and into memory for processing, they are converted to the most general datatype
(8-byte signed integer). And so for the most part, "storage class" is
indistinguishable from "datatype" and the two terms can be used
interchangeably.
*/
module dextool.plugin.mutate.backend.database;

import core.time : Duration, dur;
import logger = std.experimental.logger;

import dextool.type : AbsolutePath;

import d2sqlite3 : sqlDatabase = Database;

/// Primary key in the database
struct Pkey(Pkeys T) {
    long payload;
    alias payload this;
}

enum Pkeys {
    mutationId,
    fileId,
}

/// Primary key in the mutation table
alias MutationId = Pkey!(Pkeys.mutationId);
/// Primary key in the files table
alias FileId = Pkey!(Pkeys.fileId);

struct MutationEntry {
    import dextool.plugin.mutate.backend.type;

    MutationId id;
    AbsolutePath file;
    SourceLoc sloc;
    MutationPoint mp;
    Duration timeSpentMutating;
}

struct MutationPointEntry {
    import dextool.plugin.mutate.backend.type;

    MutationPoint mp;
    AbsolutePath file;
    SourceLoc sloc;
}

struct MutationReportEntry {
    import core.time : Duration;

    long count;
    Duration time;
}

/**
 */
struct Database {
    import std.conv : to;
    import std.exception : collectException;
    import std.typecons : Nullable;
    import dextool.plugin.mutate.backend.type : MutationPoint, Mutation,
        Checksum;
    import dextool.plugin.mutate.type : MutationOrder;
    import d2sqlite3 : Row;

    private sqlDatabase* db;
    private MutationOrder mut_order;

    static auto make(AbsolutePath db, MutationOrder mut_order) @safe {
        return Database(initializeDB(db), mut_order);
    }

    // Not movable. The database should only be passed around as a reference,
    // if at all.
    @disable this(this);

    ~this() @trusted {
        destroy(db);
    }

    /// If the file has already been analyzed.
    bool isAnalyzed(const AbsolutePath p) @trusted {
        auto stmt = db.prepare("SELECT count(*) FROM files WHERE PATH=:path LIMIT 1");
        stmt.bind(":path", cast(string) p);
        auto res = stmt.execute;
        return res.oneValue!long != 0;
    }

    /// If the file has already been analyzed.
    bool isAnalyzed(const AbsolutePath p, const Checksum cs) @trusted {
        auto stmt = db.prepare(
                "SELECT count(*) FROM files WHERE PATH=:path AND checksum0=:cs0 AND checksum1=:cs1 LIMIT 1");
        stmt.bind(":path", cast(string) p);
        stmt.bind(":cs0", cs.c0);
        stmt.bind(":cs1", cs.c1);
        auto res = stmt.execute;
        return res.oneValue!long != 0;
    }

    Nullable!FileId getFileId(const AbsolutePath p) @trusted {
        auto stmt = db.prepare("SELECT id FROM files WHERE PATH=:path");
        stmt.bind(":path", cast(string) p);
        auto res = stmt.execute;

        typeof(return) rval;
        if (!res.empty) {
            rval = FileId(res.oneValue!long);
        }

        return rval;
    }

    Nullable!Checksum getFileChecksum(const AbsolutePath p) @trusted {
        import dextool.plugin.mutate.backend.utility : checksum;

        auto stmt = db.prepare("SELECT checksum0,checksum1 FROM files WHERE PATH=:path");
        stmt.bind(":path", cast(string) p);
        auto res = stmt.execute;

        typeof(return) rval;
        if (!res.empty) {
            rval = checksum(res.front.peek!long(0), res.front.peek!long(1));
        }

        return rval;
    }

    bool hasMutationPoint(const FileId id, const MutationPoint mp) @trusted {
        auto stmt = db.prepare("SELECT count(*) FROM mutation_point WHERE
                               file_id=:id AND
                               offset_begin=:begin AND
                               offset_end=:end
                               LIMIT 1");
        stmt.bind(":id", cast(long) id);
        stmt.bind(":begin", mp.offset.begin);
        stmt.bind(":end", mp.offset.end);
        auto res = stmt.execute;

        return res.oneValue!long != 0;
    }

    /** Update the status of a mutant.
     * Params:
     *  id = ?
     *  st = ?
     *  d = time spent on veryfing the mutant
     */
    void updateMutation(MutationId id, Mutation.Status st, Duration d) @trusted {
        auto stmt = db.prepare(
                "UPDATE mutation SET status=:st,time=:time WHERE mutation.id == :id");
        stmt.bind(":st", st.to!long);
        stmt.bind(":id", id.to!long);
        stmt.bind(":time", d.total!"msecs");
        stmt.execute;
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
    Nullable!MutationEntry nextMutation(Mutation.Kind[] kinds) nothrow @trusted {
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
                                   files.path
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
            if (res.empty)
                return rval;

            auto v = res.front;

            auto mp = MutationPoint(Offset(v.peek!uint(3), v.peek!uint(4)));
            mp.mutations = [Mutation(v.peek!long(1).to!(Mutation.Kind))];
            auto pkey = MutationId(v.peek!long(0));
            auto file = AbsolutePath(FileName(v.peek!string(7)));
            auto sloc = SourceLoc(v.peek!uint(5), v.peek!uint(6));

            rval = MutationEntry(pkey, file, sloc, mp, v.peek!long(2).dur!"msecs");
        }
        catch (Exception e) {
            collectException(logger.warning(e.msg));
        }

        return rval;
    }

    Nullable!MutationEntry getMutation(MutationId id) nothrow @trusted {
        import dextool.plugin.mutate.backend.type;
        import dextool.type : FileName;

        typeof(return) rval;

        try {
            auto stmt = db.prepare("SELECT
                                   mutation.id,
                                   mutation.kind,
                                   mutation.time,
                                   mutation_point.offset_begin,
                                   mutation_point.offset_end,
                                   mutation_point.line,
                                   mutation_point.column,
                                   files.path
                                   FROM mutation,mutation_point,files
                                   WHERE
                                   mutation.id == :id AND
                                   mutation.mp_id == mutation_point.id AND
                                   mutation_point.file_id == files.id");
            stmt.bind(":id", cast(long) id);
            auto res = stmt.execute;
            if (res.empty)
                return rval;

            auto v = res.front;

            auto mp = MutationPoint(Offset(v.peek!uint(3), v.peek!uint(4)));
            mp.mutations = [Mutation(v.peek!long(1).to!(Mutation.Kind))];
            auto pkey = MutationId(v.peek!long(0));
            auto file = AbsolutePath(FileName(v.peek!string(7)));
            auto sloc = SourceLoc(v.peek!uint(5), v.peek!uint(6));

            rval = MutationEntry(pkey, file, sloc, mp, v.peek!long(2).dur!"msecs");
        }
        catch (Exception e) {
            logger.warning(e.msg).collectException;
        }

        return rval;
    }

    void iterateMutants(const Mutation.Kind[] kinds, void delegate(ref Row) dg) nothrow @trusted {
        import std.algorithm : map;
        import std.format : format;

        immutable all_mutants = "SELECT
            mutation.id,
            mutation.status,
            mutation.kind,
            mutation.time,
            mutation_point.offset_begin,
            mutation_point.offset_end,
            mutation_point.line,
            mutation_point.column,
            files.path
            FROM mutation,mutation_point,files
            WHERE
            mutation.kind IN (%(%s,%)) AND
            mutation.mp_id == mutation_point.id AND
            mutation_point.file_id == files.id
            ORDER BY mutation.status";

        try {
            auto res = db.prepare(format(all_mutants, kinds.map!(a => cast(int) a))).execute;
            foreach (ref row; res) {
                dg(row);
            }
        }
        catch (Exception e) {
            logger.error(e.msg).collectException;
        }
    }

    import dextool.plugin.mutate.backend.type;

    alias aliveMutants = countMutants!(Mutation.Status.alive);
    alias killedMutants = countMutants!(Mutation.Status.killed);
    alias timeoutMutants = countMutants!(Mutation.Status.timeout);
    alias unknownMutants = countMutants!(Mutation.Status.unknown);
    alias killedByCompilerMutants = countMutants!(Mutation.Status.killedByCompiler);

    private Nullable!MutationReportEntry countMutants(int status)(const Mutation.Kind[] kinds) nothrow @trusted {
        import core.time : dur;
        import std.algorithm : map;
        import std.format : format;

        enum query = format("SELECT count(*),sum(mutation.time) FROM mutation WHERE status==%s AND kind IN (%s)",
                    status, "%(%s,%)");

        typeof(return) rval;
        try {
            auto stmt = db.prepare(format(query, kinds.map!(a => cast(int) a)));
            auto res = stmt.execute;
            if (res.empty)
                return rval;
            rval = MutationReportEntry(res.front.peek!long(0),
                    res.front.peek!long(1).dur!"msecs");
        }
        catch (Exception e) {
            logger.warning(e.msg).collectException;
        }

        return rval;
    }

    void put(const AbsolutePath p, Checksum cs) @trusted {
        if (isAnalyzed(p))
            return;

        auto stmt = db.prepare(
                "INSERT INTO files (path, checksum0, checksum1) VALUES (:path, :checksum0, :checksum1)");
        stmt.bind(":path", cast(string) p);
        stmt.bind(":checksum0", cast(long) cs.c0);
        stmt.bind(":checksum1", cast(long) cs.c1);
        stmt.execute;
    }

    /** Save mutation points found in a specific file.
     *
     * Note: this assumes a file is never added more than once.
     * If it where ever to be the mutation points would be duplicated.
     *
     * trusted: the d2sqlite3 interface is assumed to work correctly when the
     * data via bind is *ok*.
     */
    void put(const(MutationPointEntry)[] mps) @trusted {
        auto mp_stmt = db.prepare("INSERT INTO mutation_point (file_id, offset_begin, offset_end, line, column) VALUES (:fid, :begin, :end, :line, :column)");
        auto m_stmt = db.prepare(
                "INSERT INTO mutation (mp_id, kind, status) VALUES (:mp_id, :kind, :status)");

        db.begin;
        scope (success)
            db.commit;
        scope (failure)
            db.rollback;

        FileId[string] file_ids;
        foreach (a; mps) {
            if (a.file is null) {
                debug logger.trace("this should not happen. The file is null file");
                continue;
            }

            FileId id;
            // assuming it is slow to lookup in the database so cache the lookups.
            if (auto e = a.file in file_ids) {
                id = *e;
            } else if (auto e = getFileId(a.file)) {
                id = e;
                file_ids[a.file] = id;
            }

            // TODO device a way that this call to hasMutationPoint isn't
            // necessary. This is extremly slow, ~10-100x slower than adding
            // the points without a check.
            if (hasMutationPoint(id, a.mp)) {
                continue;
            }

            const long mp_id = () {
                scope (exit)
                    mp_stmt.reset;
                mp_stmt.bind(":fid", cast(long) id);
                mp_stmt.bind(":begin", a.mp.offset.begin);
                mp_stmt.bind(":end", a.mp.offset.end);
                mp_stmt.bind(":line", a.sloc.line);
                mp_stmt.bind(":column", a.sloc.column);
                mp_stmt.execute;
                return db.lastInsertRowid;
            }();

            m_stmt.bind(":mp_id", mp_id);
            foreach (k; a.mp.mutations) {
                m_stmt.bind(":kind", k.kind);
                m_stmt.bind(":status", k.status);
                m_stmt.execute;
                m_stmt.reset;
            }
        }
    }

}

private:

sqlDatabase* initializeDB(const AbsolutePath p) @trusted
in {
    assert(p.length != 0);
}
do {
    import d2sqlite3;

    try {
        return new sqlDatabase(p, SQLITE_OPEN_READWRITE);
    }
    catch (Exception e) {
        logger.trace(e.msg);
        logger.trace("Initializing a new sqlite3 database");
    }

    auto db = new sqlDatabase(p, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE);
    initializeTables( * db);
    return db;
}

immutable files_tbl = "CREATE %s TABLE %s (
    id          INTEGER PRIMARY KEY,
    path        TEXT NOT NULL,
    checksum0   INTEGER NOT NULL,
    checksum1   INTEGER NOT NULL
    )";

// line start from zero
immutable mutation_point_tbl = "CREATE %s TABLE %s (
    id              INTEGER PRIMARY KEY,
    file_id         INTEGER NOT NULL,
    offset_begin    INTEGER NOT NULL,
    offset_end      INTEGER NOT NULL,
    line            INTEGER,
    column          INTEGER,
    FOREIGN KEY(file_id) REFERENCES files(id)
    )";

// time in ms spent on verifying the mutant
immutable mutation_tbl = "CREATE %s TABLE %s (
    id      INTEGER PRIMARY KEY,
    mp_id   INTEGER NOT NULL,
    kind    INTEGER NOT NULL,
    status  INTEGER NOT NULL,
    time    INTEGER,
    FOREIGN KEY(mp_id) REFERENCES mutation_point(id)
    )";

void initializeTables(ref sqlDatabase db) {
    import std.format : format;

    // checksum is 128bit. Using a integer to better represent and search for
    // them in queries.
    db.run(format(files_tbl, "", "files"));

    db.run(format(mutation_point_tbl, "", "mutation_point"));

    db.run(format(mutation_tbl, "", "mutation"));
}
