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

The function makeUpgradeTable will then automatically find it and use it. X
 **must** be the version upgrading FROM.

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
import std.format : format;

import d2sqlite3 : SqlDatabase = Database;

immutable allTestCaseTable = "all_test_case";
immutable filesTable = "files";
immutable killedTestCaseTable = "killed_test_case";
immutable mutationPointTable = "mutation_point";
immutable mutationStatusTable = "mutation_status";
immutable mutationTable = "mutation";
immutable srcMetadataTable = "src_metadata";
immutable rawSrcMetadataTable = "raw_src_metadata";
immutable schemaVersionTable = "schema_version";

private immutable testCaseTableV1 = "test_case";

/** Initialize or open an existing database.
 *
 * Params:
 *  p = path where to initialize a new database or open an existing
 *
 * Returns: an open sqlite3 database object.
 */
SqlDatabase initializeDB(const string p) @trusted
in {
    assert(p.length != 0);
}
do {
    import d2sqlite3;

    SqlDatabase db;
    bool is_initialized;

    void setPragmas(ref SqlDatabase db) {
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
        db = SqlDatabase(p, SQLITE_OPEN_READWRITE);
        is_initialized = true;
    } catch (Exception e) {
        logger.trace(e.msg);
        logger.trace("Initializing a new sqlite3 database");
    }

    if (!is_initialized) {
        db = SqlDatabase(p, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE);
        initializeTables(db);
    }

    db.run("PRAGMA foreign_keys=OFF;");
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

immutable files4_tbl = "CREATE TABLE %s (
    id          INTEGER PRIMARY KEY,
    path        TEXT NOT NULL,
    checksum0   INTEGER NOT NULL,
    checksum1   INTEGER NOT NULL,
    lang        INTEGER,
    CONSTRAINT  unique_ UNIQUE (path)
    )";

// line start from zero
// there shall never exist two mutations points for the same file+offset.
immutable mutation_point_v1_tbl = "CREATE TABLE %s (
    id              INTEGER PRIMARY KEY,
    file_id         INTEGER NOT NULL,
    offset_begin    INTEGER NOT NULL,
    offset_end      INTEGER NOT NULL,
    line            INTEGER,
    column          INTEGER,
    FOREIGN KEY(file_id) REFERENCES files(id) ON DELETE CASCADE,
    CONSTRAINT file_offset UNIQUE (file_id, offset_begin, offset_end)
    )";

immutable mutation_point_v2_tbl = "CREATE TABLE %s (
    id              INTEGER PRIMARY KEY,
    file_id         INTEGER NOT NULL,
    offset_begin    INTEGER NOT NULL,
    offset_end      INTEGER NOT NULL,
    line            INTEGER,
    column          INTEGER,
    line_end        INTEGER,
    column_end      INTEGER,
    FOREIGN KEY(file_id) REFERENCES files(id) ON DELETE CASCADE,
    CONSTRAINT file_offset UNIQUE (file_id, offset_begin, offset_end)
    )";

// metadata about mutants that occur on a line extracted from the source code.
// It is intended to further refined.
// nomut = if the line should ignore mutants.
immutable raw_src_metadata_v1_tbl = "CREATE TABLE %s (
    id              INTEGER PRIMARY KEY,
    file_id         INTEGER NOT NULL,
    line            INTEGER,
    nomut           INTEGER,
    FOREIGN KEY(file_id) REFERENCES files(id) ON DELETE CASCADE,
    CONSTRAINT unique_line_in_file UNIQUE (file_id, line)
    )";

// Associate metadata from lines with the mutation status.
// in_t0 = mutationPointTable
// in_t1 = rawSrcMetadataTable
// t0 = mutationTable
// t1 = mutationStatusTable
// t2 = mutationPointTable
// t3 = filesTable
immutable src_metadata_v1_tbl = "CREATE VIEW %s
    AS
    SELECT
    t0.id AS mut_id,
    t1.id AS st_id,
    t2.id AS mp_id,
    t3.id AS file_id,
    (SELECT count(*) FROM %s in_t0, %s in_t1
        WHERE
        in_t0.file_id = in_t1.file_id AND
        in_t0.line = in_t1.line AND
        t2.line = in_t1.line) AS nomut
    FROM %s t0, %s t1, %s t2, %s t3
    WHERE
    t0.mp_id = t2.id AND
    t0.st_id = t1.id AND
    t2.file_id = t3.id
    ";

// time in ms spent on verifying the mutant
immutable mutation_v1_tbl = "CREATE TABLE %s (
    id      INTEGER PRIMARY KEY,
    mp_id   INTEGER NOT NULL,
    kind    INTEGER NOT NULL,
    status  INTEGER NOT NULL,
    time    INTEGER,
    FOREIGN KEY(mp_id) REFERENCES mutation_point(id) ON DELETE CASCADE
    )";

// status is deprecated. to be removed in when upgradeV5 is removed.
immutable mutation_v2_tbl = "CREATE TABLE %s (
    id      INTEGER PRIMARY KEY,
    mp_id   INTEGER NOT NULL,
    st_id   INTEGER,
    kind    INTEGER NOT NULL,
    status  INTEGER,
    time    INTEGER,
    FOREIGN KEY(mp_id) REFERENCES mutation_point(id) ON DELETE CASCADE,
    FOREIGN KEY(st_id) REFERENCES mutation_status(id),
    CONSTRAINT unique_ UNIQUE (mp_id, kind)
    )";

immutable mutation_v3_tbl = "CREATE TABLE %s (
    id      INTEGER PRIMARY KEY,
    mp_id   INTEGER NOT NULL,
    st_id   INTEGER,
    kind    INTEGER NOT NULL,
    FOREIGN KEY(mp_id) REFERENCES mutation_point(id) ON DELETE CASCADE,
    FOREIGN KEY(st_id) REFERENCES mutation_status(id),
    CONSTRAINT unique_ UNIQUE (mp_id, kind)
    )";

// the status of a mutant. if it is killed or otherwise.
// multiple mutation operators can result in the same change of the source
// code. By coupling the mutant status to the checksum of the source code
// change it means that two mutations that have the same checksum will
// "cooperate".
// TODO: change the checksum to being NOT NULL in the future. Can't for now
// when migrating to schema version 5->6.
immutable mutation_status_v1_tbl = "CREATE TABLE %s (
    id          INTEGER PRIMARY KEY,
    status      INTEGER NOT NULL,
    checksum0   INTEGER,
    checksum1   INTEGER,
    CONSTRAINT  checksum UNIQUE (checksum0, checksum1)
    )";

// time = ms spent on verifying the mutant
// timestamp = is when the status where last updated. Seconds at UTC+0.
immutable mutation_status_v2_tbl = "CREATE TABLE %s (
    id          INTEGER PRIMARY KEY,
    status      INTEGER NOT NULL,
    time        INTEGER,
    timestamp   DATETIME,
    checksum0   INTEGER,
    checksum1   INTEGER,
    CONSTRAINT  checksum UNIQUE (checksum0, checksum1)
    )";
// update_st = when the status where last updated. UTC+0.
// added_ts = when the mutant where added to the system. UTC+0.
// test_cnt = nr of times the mutant has been tested without being killed.
immutable mutation_status_v3_tbl = "CREATE TABLE %s (
    id          INTEGER PRIMARY KEY,
    status      INTEGER NOT NULL,
    time        INTEGER,
    test_cnt    INTEGER NOT NULL,
    update_ts   DATETIME,
    added_ts    DATETIME,
    checksum0   INTEGER,
    checksum1   INTEGER,
    CONSTRAINT  checksum UNIQUE (checksum0, checksum1)
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
immutable test_case_killed_v4_tbl = "CREATE TABLE %s (
    id          INTEGER PRIMARY KEY,
    st_id       INTEGER NOT NULL,
    tc_id       INTEGER NOT NULL,
    location    TEXT,
    FOREIGN KEY(st_id) REFERENCES mutation_status(id) ON DELETE CASCADE,
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

void initializeTables(ref SqlDatabase db) {
    db.run(format(files_tbl, filesTable));
    db.run(format(mutation_point_v1_tbl, mutationPointTable));
    db.run(format(mutation_v1_tbl, mutationTable));
}

void updateSchemaVersion(ref SqlDatabase db, long ver) {
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

long getSchemaVersion(ref SqlDatabase db) {
    enum version_q = "SELECT version FROM " ~ schemaVersionTable;
    auto stmt = db.prepare(version_q);
    auto res = stmt.execute;
    if (!res.empty)
        return res.oneValue!long;
    return 0;
}

void upgrade(ref SqlDatabase db) nothrow {
    import d2sqlite3;

    alias upgradeFunc = void function(ref SqlDatabase db);
    enum tbl = makeUpgradeTable;

    while (true) {
        long version_ = 0;

        try {
            version_ = getSchemaVersion(db);
        } catch (Exception e) {
            logger.trace(e.msg).collectException;
        }

        if (version_ == tbl.latestSchemaVersion)
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
                logger.trace(e).collectException;
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
void upgradeV0(ref SqlDatabase db) {
    db.run(format(version_tbl, schemaVersionTable));
    updateSchemaVersion(db, 1);
}

/// 2018-04-08
void upgradeV1(ref SqlDatabase db) {
    db.run(format(test_case_killed_v1_tbl, testCaseTableV1));
    updateSchemaVersion(db, 2);
}

/// 2018-04-22
void upgradeV2(ref SqlDatabase db) {
    immutable new_tbl = "new_" ~ filesTable;
    db.run(format(files3_tbl, new_tbl));
    db.run(format("INSERT INTO %s (id,path,checksum0,checksum1) SELECT * FROM %s",
            new_tbl, filesTable));
    db.run(format("DROP TABLE %s", filesTable));
    db.run(format("ALTER TABLE %s RENAME TO %s", new_tbl, filesTable));

    updateSchemaVersion(db, 3);
}

/// 2018-09-01
void upgradeV3(ref SqlDatabase db) {
    immutable new_tbl = "new_" ~ testCaseTableV1;
    db.run(format(test_case_killed_v2_tbl, new_tbl));
    db.run(format("INSERT INTO %s (id,mut_id,name) SELECT * FROM %s", new_tbl, testCaseTableV1));
    db.run(format("DROP TABLE %s", testCaseTableV1));
    db.run(format("ALTER TABLE %s RENAME TO %s", new_tbl, killedTestCaseTable));

    db.run(format(all_test_case_tbl, allTestCaseTable));

    updateSchemaVersion(db, 4);
}

/// 2018-09-24
void upgradeV4(ref SqlDatabase db) {
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

/** 2018-09-30
 *
 * This upgrade will drop all existing mutations and thus all results.
 * It is too complex trying to upgrade and keep the results.
 *
 * When removing this function also remove the status field in mutation_v2_tbl.
 */
void upgradeV5(ref SqlDatabase db) {
    db.run("PRAGMA foreign_keys=OFF;");
    scope (exit)
        db.run("PRAGMA foreign_keys=ON;");

    db.run(format(mutation_status_v1_tbl, mutationStatusTable));

    immutable new_mut_tbl = "new_" ~ mutationTable;

    db.run(format("DROP TABLE %s", mutationTable));
    db.run(format(mutation_v2_tbl, mutationTable));

    immutable new_files_tbl = "new_" ~ filesTable;
    db.run(format(files4_tbl, new_files_tbl));
    db.run(format("INSERT OR IGNORE INTO %s (id,path,checksum0,checksum1,lang) SELECT * FROM %s",
            new_files_tbl, filesTable));
    db.run(format("DROP TABLE %s", filesTable));
    db.run(format("ALTER TABLE %s RENAME TO %s", new_files_tbl, filesTable));

    updateSchemaVersion(db, 6);
}

/// 2018-10-11
void upgradeV6(ref SqlDatabase db) {
    db.run("PRAGMA foreign_keys=OFF;");
    scope (exit)
        db.run("PRAGMA foreign_keys=ON;");

    enum new_mut_tbl = "new_" ~ mutationTable;
    db.run(format(mutation_v3_tbl, new_mut_tbl));
    db.run(format("INSERT INTO %s (id,mp_id,st_id,kind) SELECT id,mp_id,st_id,kind FROM %s",
            new_mut_tbl, mutationTable));
    db.run(format("DROP TABLE %s", mutationTable));
    db.run(format("ALTER TABLE %s RENAME TO %s", new_mut_tbl, mutationTable));

    enum new_muts_tbl = "new_" ~ mutationStatusTable;
    db.run(format(mutation_status_v2_tbl, new_muts_tbl));
    db.run(format("INSERT INTO %s (id,status,checksum0,checksum1) SELECT id,status,checksum0,checksum1 FROM %s",
            new_muts_tbl, mutationStatusTable));
    db.run(format("DROP TABLE %s", mutationStatusTable));
    db.run(format("ALTER TABLE %s RENAME TO %s", new_muts_tbl, mutationStatusTable));

    updateSchemaVersion(db, 7);
}

/// 2018-10-15
void upgradeV7(ref SqlDatabase db) {
    db.run("PRAGMA foreign_keys=OFF;");
    scope (exit)
        db.run("PRAGMA foreign_keys=ON;");

    enum new_tbl = "new_" ~ killedTestCaseTable;
    db.run(format(test_case_killed_v4_tbl, new_tbl));
    db.run(format("INSERT INTO %s (id,st_id,tc_id,location)
        SELECT t0.id,t1.st_id,t0.tc_id,t0.location
        FROM %s t0, %s t1
        WHERE
        t0.mut_id = t1.id", new_tbl,
            killedTestCaseTable, mutationTable));

    db.run(format("DROP TABLE %s", killedTestCaseTable));
    db.run(format("ALTER TABLE %s RENAME TO %s", new_tbl, killedTestCaseTable));

    updateSchemaVersion(db, 8);
}

/// 2018-10-20
void upgradeV8(ref SqlDatabase db) {
    db.run("PRAGMA foreign_keys=OFF;");
    scope (exit)
        db.run("PRAGMA foreign_keys=ON;");

    enum new_tbl = "new_" ~ mutationPointTable;
    db.run(format(mutation_point_v2_tbl, new_tbl));
    db.run(format("INSERT INTO %s (id,file_id,offset_begin,offset_end,line,column)
        SELECT t0.id,t0.file_id,t0.offset_begin,t0.offset_end,t0.line,t0.column
        FROM %s t0",
            new_tbl, mutationPointTable));

    replaceTbl(db, new_tbl, mutationPointTable);
    updateSchemaVersion(db, 9);
}

/// 2018-11-10
void upgradeV9(ref SqlDatabase db) {
    db.run("PRAGMA foreign_keys=OFF;");
    scope (exit)
        db.run("PRAGMA foreign_keys=ON;");

    enum new_tbl = "new_" ~ mutationStatusTable;
    db.run(format(mutation_status_v3_tbl, new_tbl));
    db.run(format("INSERT INTO %s (id,status,time,test_cnt,update_ts,checksum0,checksum1)
        SELECT t0.id,t0.status,t0.time,0,t0.timestamp,t0.checksum0,t0.checksum1
        FROM %s t0",
            new_tbl, mutationStatusTable));

    replaceTbl(db, new_tbl, mutationStatusTable);
    updateSchemaVersion(db, 10);
}

/// 2018-11-25
void upgradeV10(ref SqlDatabase db) {
    db.run(format(raw_src_metadata_v1_tbl, rawSrcMetadataTable));
    db.run(format(src_metadata_v1_tbl, srcMetadataTable, mutationPointTable,
            rawSrcMetadataTable, mutationTable, mutationStatusTable,
            mutationPointTable, filesTable));
    updateSchemaVersion(db, 11);
}

void replaceTbl(ref SqlDatabase db, string src, string dst) {
    db.run(format("DROP TABLE %s", dst));
    db.run(format("ALTER TABLE %s RENAME TO %s", src, dst));
}

struct UpgradeTable {
    alias UpgradeFunc = void function(ref SqlDatabase db);
    UpgradeFunc[long] tbl;
    alias tbl this;

    immutable long latestSchemaVersion;
}

/** Inspects a module for functions starting with upgradeV to create a table of
 * functions that can be used to upgrade a database.
 */
UpgradeTable makeUpgradeTable() {
    import std.algorithm : sort, startsWith;
    import std.conv : to;
    import std.typecons : Tuple;

    immutable prefix = "upgradeV";

    alias Module = dextool.plugin.mutate.backend.database.schema;

    // the second parameter is the database version to upgrade FROM.
    alias UpgradeFx = Tuple!(UpgradeTable.UpgradeFunc, long);

    UpgradeFx[] upgradeFx;
    long last_from;

    static foreach (member; __traits(allMembers, Module)) {
        static if (member.startsWith(prefix))
            upgradeFx ~= UpgradeFx(&__traits(getMember, Module, member),
                    member[prefix.length .. $].to!long);
    }

    typeof(UpgradeTable.tbl) tbl;
    foreach (fn; upgradeFx.sort!((a, b) => a[1] < b[1])) {
        last_from = fn[1];
        tbl[last_from] = fn[0];
    }

    return UpgradeTable(tbl, last_from + 1);
}
