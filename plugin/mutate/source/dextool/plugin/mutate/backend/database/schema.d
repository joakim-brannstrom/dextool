/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains the schema to initialize the database.

# Style
A database schema upgrade path shall have a comment stating what date it was added.
Each change to the database schema must have an equal upgrade added.

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
module dextool.plugin.mutate.backend.database.schema;

import std.exception : collectException;
import logger = std.experimental.logger;

import d2sqlite3 : sqlDatabase = Database;

enum latestSchemaVersion = 2;

/** Initialize or open an existing database.
 *
 * Params:
 *  p = path where to initialize a new database or open an existing
 *
 * Returns: an open sqlite3 database object.
 */
sqlDatabase* initializeDB(const string p) @trusted
in {
    assert(p.length != 0);
}
do {
    import d2sqlite3;

    sqlDatabase* db;

    void setPragmas(sqlDatabase* db) {
        // dfmt off
        auto pragmas = [
            // required for foreign keys with cascade to work
            "PRAGMA foreign_keys=ON;",
            // use two worker threads. Should improve performance a bit without having an adverse effect.
            // this should probably be user configurable.
            "PRAGMA threads = 2;",
        ];
        // dfmt on

        foreach (p; pragmas) {
            db.run(p);
        }
    }

    try {
        db = new sqlDatabase(p, SQLITE_OPEN_READWRITE);
        upgrade(*db);
    }
    catch (Exception e) {
        logger.trace(e.msg);
        logger.trace("Initializing a new sqlite3 database");
    }

    if (db is null) {
        db = new sqlDatabase(p, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE);
        initializeTables(*db);
    }

    setPragmas(db);

    return db;
}

private:

immutable version_tbl = "CREATE TABLE %s (
    version     INTEGER NOT NULL
    )";

// checksum is 128bit. Using a integer to better represent and search for them
// in queries.
immutable files_tbl = "CREATE TABLE %s (
    id          INTEGER PRIMARY KEY,
    path        TEXT NOT NULL,
    checksum0   INTEGER NOT NULL,
    checksum1   INTEGER NOT NULL
    )";

// line start from zero
// there shall never exist two mutations points for the same file+offset.
immutable mutation_point_tbl = "CREATE TABLE %s (
    id              INTEGER PRIMARY KEY,
    file_id         INTEGER NOT NULL,
    offset_begin    INTEGER NOT NULL,
    offset_end      INTEGER NOT NULL,
    line            INTEGER,
    column          INTEGER,
    FOREIGN KEY(file_id) REFERENCES files(id) ON DELETE CASCADE,
    CONSTRAINT file_offset UNIQUE (file_id, offset_begin, offset_end)
    )";

// time in ms spent on verifying the mutant
immutable mutation_tbl = "CREATE TABLE %s (
    id      INTEGER PRIMARY KEY,
    mp_id   INTEGER NOT NULL,
    kind    INTEGER NOT NULL,
    status  INTEGER NOT NULL,
    time    INTEGER,
    FOREIGN KEY(mp_id) REFERENCES mutation_point(id) ON DELETE CASCADE
    )";

// raw_id is whatever identifier the user chose
immutable test_case_track_tbl = "CREATE TABLE %s (
    id      INTEGER PRIMARY KEY,
    mut_id  INTEGER NOT NULL,
    raw_id  TEXT NOT NULL,
    FOREIGN KEY(mut_id) REFERENCES mutation(id) ON DELETE CASCADE
    )";

void initializeTables(ref sqlDatabase db) {
    import std.format : format;

    db.run(format(version_tbl, "schema_version"));
    updateSchemaVersion(db, latestSchemaVersion);

    db.run(format(files_tbl, "files"));
    db.run(format(mutation_point_tbl, "mutation_point"));
    db.run(format(mutation_tbl, "mutation"));
    db.run(format(test_case_track_tbl, "test_case"));
}

void updateSchemaVersion(ref sqlDatabase db, long ver) {
    try {
        auto stmt = db.prepare("INSERT INTO schema_version (version) VALUES(:ver)");
        stmt.bind(":ver", ver);
        stmt.execute;
    }
    catch (Exception e) {
        auto stmt = db.prepare("UPDATE schema_version SET version=:ver");
        stmt.bind(":ver", ver);
        stmt.execute;
    }
}

void upgrade(ref sqlDatabase db) nothrow {
    import d2sqlite3;

    alias upgradeFunc = void function(ref sqlDatabase db);
    upgradeFunc[long] tbl;

    tbl[0] = &upgradeV0;
    tbl[1] = &upgradeV1;

    while (true) {
        long version_ = 0;

        try {
            enum version_q = "SELECT version FROM schema_version";
            auto stmt = db.prepare(version_q);
            auto res = stmt.execute;
            if (!res.empty)
                version_ = res.oneValue!long;
        }
        catch (Exception e) {
            logger.trace(e.msg).collectException;
        }

        if (version_ == latestSchemaVersion)
            return;

        logger.infof("Upgrading database from %s", version_).collectException;

        if (auto f = version_ in tbl) {
            try {
                db.begin;
                scope (success)
                    db.commit;
                scope (failure)
                    db.rollback;
                (*f)(db);
            }
            catch (Exception e) {
                logger.error(e.msg).collectException;
                logger.warningf("Unable to upgrade a database of version %s",
                        version_).collectException;
                logger.warning("This might impact the functionality. It is unwise to continue")
                    .collectException;
            }
        } else {
            logger.info("Upgrade successful").collectException;
            return;
        }
    }
}

/// 2018-04-07
void upgradeV0(ref sqlDatabase db) {
    import std.format : format;

    db.run(format(version_tbl, "schema_version"));
    updateSchemaVersion(db, 1);
}

/// 2018-04-08
void upgradeV1(ref sqlDatabase db) {
    import std.format : format;

    db.run(format(test_case_track_tbl, "test_case"));
    updateSchemaVersion(db, 2);
}
