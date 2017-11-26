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
    MutationPoint mp;
}

struct MutationPointEntry {
    import dextool.plugin.mutate.backend.type;

    MutationPoint mp;
    AbsolutePath file;
}

/**
 */
struct Database {
    import std.conv : to;
    import std.typecons : Nullable;
    import dextool.plugin.mutate.backend.type : MutationPoint, Mutation,
        Checksum;

    private sqlDatabase* db;

    static auto make(AbsolutePath db) @safe {
        import dextool.type : FileName;

        return Database(initializeDB(db));
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
     */
    void updateMutation(MutationId id, Mutation.Status st) @trusted {
        auto stmt = db.prepare("UPDATE mutation SET status = :st WHERE mutation.id == :id");
        stmt.bind(":st", st.to!long);
        stmt.bind(":id", id.to!long);
        stmt.execute;
    }

    /** Get the next mutation point + 1 mutant for it that has status unknown.
     *
     * TODO to run many instances in parallel the mutation should be locked.
     *
     * The chosen point is randomised.
     */
    Nullable!MutationEntry nextMutation() nothrow @trusted {
        import std.exception : collectException;
        import dextool.plugin.mutate.backend.type;
        import dextool.type : FileName;

        typeof(return) rval;

        try {
            auto stmt = db.prepare("SELECT
                                   mutation.id,
                                   mutation.kind,
                                   mutation_point.offset_begin,
                                   mutation_point.offset_end,
                                   files.path
                                   FROM mutation,mutation_point,files
                                   WHERE
                                   mutation.status == 0 AND
                                   mutation.mp_id == mutation_point.id AND
                                   mutation_point.file_id == files.id AND
                                   mutation.id IN (SELECT id FROM mutation ORDER BY RANDOM() LIMIT 1)");
            auto res = stmt.execute;
            if (res.empty)
                return rval;

            auto v = res.front;

            auto mp = MutationPoint(Offset(v.peek!uint(2), v.peek!uint(3)));
            mp.mutations = [Mutation(v.peek!long(1).to!(Mutation.Kind))];
            auto pkey = MutationId(v.peek!long(0));
            auto file = AbsolutePath(FileName(v.peek!string(4)));

            rval = MutationEntry(pkey, file, mp);
        }
        catch (Exception e) {
            collectException(logger.warning(e.msg));
        }

        return rval;
    }

    Nullable!MutationEntry getMutation(MutationId id) nothrow @trusted {
        import std.exception : collectException;
        import dextool.plugin.mutate.backend.type;
        import dextool.type : FileName;

        typeof(return) rval;

        try {
            auto stmt = db.prepare("SELECT
                                   mutation.id,
                                   mutation.kind,
                                   mutation_point.offset_begin,
                                   mutation_point.offset_end,
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

            auto mp = MutationPoint(Offset(v.peek!uint(2), v.peek!uint(3)));
            mp.mutations = [Mutation(v.peek!long(1).to!(Mutation.Kind))];
            auto pkey = MutationId(v.peek!long(0));
            auto file = AbsolutePath(FileName(v.peek!string(4)));

            rval = MutationEntry(pkey, file, mp);
        }
        catch (Exception e) {
            collectException(logger.warning(e.msg));
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
     * trusted: the d2sqlite3 interface is assumed to work correctly when the
     * data via bind is *ok*.
     */
    void put(const(MutationPointEntry)[] mps) @trusted {
        auto mp_stmt = db.prepare(
                "INSERT INTO mutation_point (file_id, offset_begin, offset_end) VALUES (:fid, :begin, :end)");
        auto m_stmt = db.prepare(
                "INSERT INTO mutation (mp_id, kind, status) VALUES (:mp_id, :kind, :status)");

        db.begin;
        scope (success)
            db.commit;
        scope (failure)
            db.rollback;

        FileId[string] file_ids;
        foreach (a; mps) {
            FileId id;

            if (a.file is null) {
                debug logger.trace("this should not happen. The file is null file");
                continue;
            }

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

void initializeTables(ref sqlDatabase db) {
    // checksum is 128bit. Using a integer to better represent and search for
    // them in queries.
    db.run("CREATE TABLE files (
    id          INTEGER PRIMARY KEY,
    path        TEXT NOT NULL,
    checksum0   INTEGER NOT NULL,
    checksum1   INTEGER NOT NULL
    )");

    db.run("CREATE TABLE mutation_point (
    id              INTEGER PRIMARY KEY,
    file_id         INTEGER NOT NULL,
    offset_begin    INTEGER NOT NULL,
    offset_end      INTEGER NOT NULL,
    FOREIGN KEY(file_id) REFERENCES files(id)
    )");

    db.run("CREATE TABLE mutation (
    id      INTEGER PRIMARY KEY,
    mp_id   INTEGER NOT NULL,
    kind    INTEGER NOT NULL,
    status  INTEGER NOT NULL,
    FOREIGN KEY(mp_id) REFERENCES mutation_point(id)
    )");
}
