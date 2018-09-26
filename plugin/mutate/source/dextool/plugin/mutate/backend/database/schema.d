/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains the schema to initialize the database.

To ensure that the upgrade path for a database always work a database is
created at the "lowest supported" and upgraded to the latest.

# How to add schema change

1. add an upgrade function, upgradeVX.
2. add the upgrade function to the upgrade functions tbl.
3. increment the latest schema counter, `latestSchemaVersion`.

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

import logger = std.experimental.logger;
import std.exception : collectException;

import d2sqlite3 : sqlDatabase = Database;

immutable latestSchemaVersion = 5;
immutable schemaVersionTable = "schema_version";
immutable filesTable = "files";
immutable mutationPointTable = "mutation_point";
immutable mutationTable = "mutation";
immutable killedTestCaseTable = "killed_test_case";
immutable allTestCaseTable = "all_test_case";

private immutable testCaseTableV1 = "test_case";

/** Initialize or open an existing database.
 *
 * Params:
 *  p = path where to initialize a new database or open an existing
 *
 * Returns: an open sqlite3 database object.
 */
sqlDatabase initializeDB(const string p) @trusted
in {
    assert(p.length != 0);
}
do {
    import d2sqlite3;

    sqlDatabase db;
    bool is_initialized;

    void setPragmas(ref sqlDatabase db) {
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
        db = sqlDatabase(p, SQLITE_OPEN_READWRITE);
        is_initialized = true;
    } catch (Exception e) {
        logger.trace(e.msg);
        logger.trace("Initializing a new sqlite3 database");
    }

    if (!is_initialized) {
        db = sqlDatabase(p, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE);
        initializeTables(db);
    }

    upgrade(db);
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

/// upgraded table with support for the language
immutable files3_tbl = "CREATE TABLE %s (
    id          INTEGER PRIMARY KEY,
    path        TEXT NOT NULL,
    checksum0   INTEGER NOT NULL,
    checksum1   INTEGER NOT NULL,
    lang        INTEGER
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

// test_case is whatever identifier the user choose.
// this could use an intermediate adapter table to normalise the test_case data
// but I chose not to do that because it makes it harder to add test cases and
// do a cleanup.
immutable test_case_killed_v1_tbl = "CREATE TABLE %s (
    id          INTEGER PRIMARY KEY,
    mut_id      INTEGER NOT NULL,
    test_case   TEXT NOT NULL,
    FOREIGN KEY(mut_id) REFERENCES mutation(id) ON DELETE CASCADE
    )";
// location is a filesystem location or other suitable helper for a user to locate the test.
immutable test_case_killed_v2_tbl = "CREATE TABLE %s (
    id          INTEGER PRIMARY KEY,
    mut_id      INTEGER NOT NULL,
    name        TEXT NOT NULL,
    location    TEXT,
    FOREIGN KEY(mut_id) REFERENCES mutation(id) ON DELETE CASCADE
    )";
immutable test_case_killed_v3_tbl = "CREATE TABLE %s (
    id          INTEGER PRIMARY KEY,
    mut_id      INTEGER NOT NULL,
    tc_id       INTEGER NOT NULL,
    location    TEXT,
    FOREIGN KEY(mut_id) REFERENCES mutation(id) ON DELETE CASCADE,
    FOREIGN KEY(tc_id) REFERENCES all_test_case(id) ON DELETE CASCADE
    )";

// Track all test cases that has been found by the test suite output analyzer.
// Useful to find test cases that has never killed any mutant.
// name should match test_case_killed_v2_tbl
// TODO: name should be the primary key. on a conflict a counter should be updated.
immutable all_test_case_tbl = "CREATE TABLE %s (
    id          INTEGER PRIMARY KEY,
    name        TEXT NOT NULL
    )";

void initializeTables(ref sqlDatabase db) {
    import std.format : format;

    db.run(format(files_tbl, filesTable));
    db.run(format(mutation_point_tbl, mutationPointTable));
    db.run(format(mutation_tbl, mutationTable));
}

void updateSchemaVersion(ref sqlDatabase db, long ver) {
    import std.format : format;

    try {
        auto stmt = db.prepare(format("DELETE FROM %s", schemaVersionTable));
        stmt.execute;

        stmt = db.prepare(format("INSERT INTO %s (version) VALUES(:ver)", schemaVersionTable));
        stmt.bind(":ver", ver);
        stmt.execute;
    } catch (Exception e) {
        logger.error(e.msg).collectException;
    }
}

long getSchemaVersion(ref sqlDatabase db) {
    enum version_q = "SELECT version FROM " ~ schemaVersionTable;
    auto stmt = db.prepare(version_q);
    auto res = stmt.execute;
    if (!res.empty)
        return res.oneValue!long;
    return 0;
}

void upgrade(ref sqlDatabase db) nothrow {
    import d2sqlite3;

    alias upgradeFunc = void function(ref sqlDatabase db);
    upgradeFunc[long] tbl;

    tbl[0] = &upgradeV0;
    tbl[1] = &upgradeV1;
    tbl[2] = &upgradeV2;
    tbl[3] = &upgradeV3;
    tbl[4] = &upgradeV4;

    while (true) {
        long version_ = 0;

        try {
            version_ = getSchemaVersion(db);
        } catch (Exception e) {
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
            } catch (Exception e) {
                logger.error(e.msg).collectException;
                logger.warningf("Unable to upgrade a database of version %s",
                        version_).collectException;
                logger.warning("This might impact the functionality. It is unwise to continue")
                    .collectException;
                return;
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

    db.run(format(version_tbl, schemaVersionTable));
    updateSchemaVersion(db, 1);
}

/// 2018-04-08
void upgradeV1(ref sqlDatabase db) {
    import std.format : format;

    db.run(format(test_case_killed_v1_tbl, testCaseTableV1));
    updateSchemaVersion(db, 2);
}

/// 2018-04-22
void upgradeV2(ref sqlDatabase db) {
    import std.format : format;

    immutable new_tbl = "new_" ~ filesTable;
    db.run(format(files3_tbl, new_tbl));
    db.run(format("INSERT INTO %s (id,path,checksum0,checksum1) SELECT * FROM %s",
            new_tbl, filesTable));
    db.run(format("DROP TABLE %s", filesTable));
    db.run(format("ALTER TABLE %s RENAME TO %s", new_tbl, filesTable));

    updateSchemaVersion(db, 3);
}

/// 2018-09-01
void upgradeV3(ref sqlDatabase db) {
    import std.format : format;

    immutable new_tbl = "new_" ~ testCaseTableV1;
    db.run(format(test_case_killed_v2_tbl, new_tbl));
    db.run(format("INSERT INTO %s (id,mut_id,name) SELECT * FROM %s", new_tbl, testCaseTableV1));
    db.run(format("DROP TABLE %s", testCaseTableV1));
    db.run(format("ALTER TABLE %s RENAME TO %s", new_tbl, killedTestCaseTable));

    db.run(format(all_test_case_tbl, allTestCaseTable));

    updateSchemaVersion(db, 4);
}

/// 2018-09-24
void upgradeV4(ref sqlDatabase db) {
    import std.format : format;

    immutable new_tbl = "new_" ~ killedTestCaseTable;
    db.run(format(test_case_killed_v3_tbl, new_tbl));

    // add all missing test cases to all_test_case
    db.run(format("INSERT INTO %s (name) SELECT DISTINCT t1.name FROM %s t1 LEFT JOIN %s t2 ON t2.name = t1.name WHERE t2.name IS NULL",
            allTestCaseTable, killedTestCaseTable, allTestCaseTable));
    // https://stackoverflow.com/questions/2686254/how-to-select-all-records-from-one-table-that-do-not-exist-in-another-table
    //Q: What is happening here?
    //
    //A: Conceptually, we select all rows from table1 and for each row we
    //attempt to find a row in table2 with the same value for the name column.
    //If there is no such row, we just leave the table2 portion of our result
    //empty for that row. Then we constrain our selection by picking only those
    //rows in the result where the matching row does not exist. Finally, We
    //ignore all fields from our result except for the name column (the one we
    //are sure that exists, from table1).
    //
    //While it may not be the most performant method possible in all cases, it
    //should work in basically every database engine ever that attempts to
    //implement ANSI 92 SQL

    // This do NOT WORK. The result is that that this upgrade is broken because
    // it drops all maps between killed_test_case and mutation.
    //db.run(format("INSERT INTO %s (id,mut_id,tc_id,location) SELECT t1.id,t1.mut_id,t2.id,t1.location FROM %s t1 INNER JOIN %s t2 ON t1.name = t2.name",
    //        new_tbl, killedTestCaseTable, allTestCaseTable));

    db.run(format("DROP TABLE %s", killedTestCaseTable));
    db.run(format("ALTER TABLE %s RENAME TO %s", new_tbl, killedTestCaseTable));

    updateSchemaVersion(db, 5);
}
