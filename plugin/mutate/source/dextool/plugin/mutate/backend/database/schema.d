/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains the schema to initialize the database.

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

import logger = std.experimental.logger;

import d2sqlite3 : sqlDatabase = Database;

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

    void setPragmas(sqlDatabase* db) {
        // dfmt off
        auto pragmas = [
            // required for foreign keys with cascade to work
            "PRAGMA foreign_keys=ON;"
        ];
        // dfmt on

        foreach (p; pragmas) {
            db.run(p);
        }
    }

    try {
        auto db = new sqlDatabase(p, SQLITE_OPEN_READWRITE);
        setPragmas(db);
        return db;
    }
    catch (Exception e) {
        logger.trace(e.msg);
        logger.trace("Initializing a new sqlite3 database");
    }

    auto db = new sqlDatabase(p, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE);
    setPragmas(db);

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
// there shall never exist two mutations points for the same file+offset.
immutable mutation_point_tbl = "CREATE %s TABLE %s (
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
immutable mutation_tbl = "CREATE %s TABLE %s (
    id      INTEGER PRIMARY KEY,
    mp_id   INTEGER NOT NULL,
    kind    INTEGER NOT NULL,
    status  INTEGER NOT NULL,
    time    INTEGER,
    FOREIGN KEY(mp_id) REFERENCES mutation_point(id) ON DELETE CASCADE
    )";

void initializeTables(ref sqlDatabase db) {
    import std.format : format;

    // checksum is 128bit. Using a integer to better represent and search for
    // them in queries.
    db.run(format(files_tbl, "", "files"));

    db.run(format(mutation_point_tbl, "", "mutation_point"));

    db.run(format(mutation_tbl, "", "mutation"));
}
