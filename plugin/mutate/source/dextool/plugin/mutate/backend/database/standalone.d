/**
Copyright: Copyright (c) 2018-2021, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains the a basic database interface that have minimal
dependencies on internal modules.  It is intended to be reusable from the test
suite.

The only acceptable dependency are:
 * ../type.d
 * ..backend/type.d
 * ../database/type.d
 * ../database/schema.d
*/
module dextool.plugin.mutate.backend.database.standalone;

import core.time : Duration, dur;
import logger = std.experimental.logger;
import std.algorithm : copy, map, joiner, filter;
import std.array : Appender, appender, array, empty;
import std.conv : to;
import std.datetime : SysTime, Clock;
import std.exception : collectException;
import std.format : format;
import std.path : relativePath;
import std.range : enumerate;
import std.regex : Regex, matchFirst;
import std.typecons : Nullable, Flag, No;

import d2sqlite3 : SqlDatabase = Database;
import miniorm : Miniorm, select, insert, insertOrReplace, delete_,
    insertOrIgnore, toSqliteDateTime, fromSqLiteDateTime, Bind;
import my.gc.refc;
import my.named_type;
import my.optional;
import my.set;
import my.term_color;

import dextool.type : AbsolutePath, Path, ExitStatusType;

import dextool.plugin.mutate.backend.database.schema;
import dextool.plugin.mutate.backend.database.type;
import dextool.plugin.mutate.backend.type : MutationPoint, Mutation, Checksum,
    Language, Offset, TestCase, SourceLoc, SchemataChecksum;
import dextool.plugin.mutate.type : MutationOrder;

/** Database wrapper with minimal dependencies.
 */
struct Database {
    private {
        Miniorm db_;
        DbDependency dbDependency_;
        DbTestCmd dbTestCmd_;
        DbTestCase dbTestCase_;
        DbMutant dbMutant_;
        DbWorklist dbWorklist_;
        DbMemOverload dbMemOverload_;
        DbMarkMutant dbMarkMutant_;
        DbTimeout dbTimeout_;
        DbCoverage dbCoverage_;
        DbSchema dbSchema_;
        DbTestFile dbTestFile_;
        DbMetaData dbMetaData_;
    }

    /** Create a database by either opening an existing or initializing a new.
     *
     * Params:
     *  db = path to the database
     */
    static auto make(string db) @trusted {
        return Database(initializeDB(db));
    }

    scope ref Miniorm db() return @safe {
        return db_;
    }

    scope auto transaction() @trusted {
        return db.transaction;
    }

    void run(string sql) {
        db.run(sql);
    }

    bool isToolVersionDifferent(ToolVersion compareTo) @trusted {
        foreach (a; db.run(select!DextoolVersionTable)) {
            return a.checksum != compareTo.get;
        }
        // if there is no tool version recorded then assume it is different.
        return true;
    }

    /// Update the version of the tool.
    void updateToolVersion(const ToolVersion tv) @trusted {
        db.run(delete_!DextoolVersionTable);
        db.run(insert!DextoolVersionTable, DextoolVersionTable(tv.get));
    }

    /// If the file has already been analyzed.
    bool isAnalyzed(const Path p) @trusted {
        auto stmt = db.prepare("SELECT count(*) FROM files WHERE path=:path LIMIT 1");
        stmt.get.bind(":path", cast(string) p);
        auto res = stmt.get.execute;
        return res.oneValue!long != 0;
    }

    /// If the file has already been analyzed.
    bool isAnalyzed(const Path p, const Checksum cs) @trusted {
        auto stmt = db.prepare(
                "SELECT count(*) FROM files WHERE path=:path AND checksum0=:cs0 AND checksum1=:cs1 LIMIT 1");
        stmt.get.bind(":path", cast(string) p);
        stmt.get.bind(":cs0", cast(long) cs.c0);
        stmt.get.bind(":cs1", cast(long) cs.c1);
        auto res = stmt.get.execute;
        return res.oneValue!long != 0;
    }

    Nullable!FileId getFileId(const Path p) @trusted {
        static immutable sql = format("SELECT id FROM %s WHERE path=:path", filesTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":path", p.toString);
        auto res = stmt.get.execute;

        typeof(return) rval;
        if (!res.empty)
            rval = FileId(res.oneValue!long);
        return rval;
    }

    /// Returns: the path ID for the mutant.
    Nullable!FileId getFileId(const MutationId id) @trusted {
        static immutable sql = format("SELECT t1.file_id
            FROM %s t0, %s t1
            WHERE t0.id = :id AND t0.mp_id = t1.id", mutationTable, mutationPointTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", cast(long) id);

        typeof(return) rval;
        foreach (ref r; stmt.get.execute)
            rval = FileId(r.peek!long(0));
        return rval;
    }

    /// Returns: the file path that the id correspond to.
    Nullable!Path getFile(const FileId id) @trusted {
        static immutable sql = format("SELECT path FROM %s WHERE id = :id", filesTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", id.get);

        typeof(return) rval;
        foreach (ref r; stmt.get.execute)
            rval = Path(r.peek!string(0));
        return rval;
    }

    Optional!Language getFileIdLanguage(const FileId id) @trusted {
        static immutable sql = format!"SELECT lang FROM %s WHERE id = :id"(filesTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", id.get);

        foreach (ref r; stmt.get.execute)
            return some(r.peek!ubyte(0).to!Language);
        return none!Language;
    }

    /// Returns: all files tagged as a root.
    FileId[] getRootFiles() @trusted {
        static immutable sql = format!"SELECT id FROM %s WHERE root=1"(filesTable);

        auto app = appender!(FileId[])();
        auto stmt = db.prepare(sql);
        foreach (ref r; stmt.get.execute) {
            app.put(r.peek!long(0).FileId);
        }
        return app.data;
    }

    /// Remove the file with all mutations that are coupled to it.
    void removeFile(const Path p) @trusted {
        static immutable sql = "DELETE FROM " ~ filesTable ~ " WHERE path=:path";
        auto stmt = db.prepare(sql);
        stmt.get.bind(":path", p.toString);
        stmt.get.execute;
    }

    /// Returns: All files in the database as relative paths.
    Path[] getFiles() @trusted {
        auto stmt = db.prepare(format!"SELECT path FROM %s"(filesTable));
        auto res = stmt.get.execute;

        auto app = appender!(Path[]);
        foreach (ref r; res) {
            app.put(Path(r.peek!string(0)));
        }

        return app.data;
    }

    string[] getFilesStrings() return @trusted {
        auto stmt = db.prepare(format!"SELECT path FROM %s"(filesTable));
        auto res = stmt.get.execute;

        auto app = appender!(string[]);
        foreach (ref r; res) {
            app.put(r.peek!string(0));
        }

        return app.data;
    }

    Nullable!Checksum getFileChecksum(const Path p) @trusted {
        static immutable sql = "SELECT checksum0,checksum1 FROM " ~ filesTable ~ " WHERE path=:path";
        auto stmt = db.prepare(sql);
        stmt.get.bind(":path", p.toString);
        auto res = stmt.get.execute;

        typeof(return) rval;
        if (!res.empty) {
            rval = Checksum(res.front.peek!long(0), res.front.peek!long(1));
        }

        return rval;
    }

    /// Returns: the timestamp of the newest file that was added.
    Optional!SysTime getNewestFile() @trusted {
        auto stmt = db.prepare(
                "SELECT timestamp FROM " ~ filesTable ~ " ORDER BY datetime(timestamp) DESC LIMIT 1");
        auto res = stmt.get.execute;

        foreach (ref r; res) {
            return some(r.peek!string(0).fromSqLiteDateTime);
        }

        return none!SysTime;
    }

    void put(const Path p, Checksum cs, const Language lang, const bool isRoot) @trusted {
        static immutable sql = format!"INSERT OR IGNORE INTO %s (path, checksum0, checksum1, lang, timestamp, root)
            VALUES (:path, :checksum0, :checksum1, :lang, :time, :root)"(filesTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":path", p.toString);
        stmt.get.bind(":checksum0", cast(long) cs.c0);
        stmt.get.bind(":checksum1", cast(long) cs.c1);
        stmt.get.bind(":lang", cast(long) lang);
        stmt.get.bind(":time", Clock.currTime.toSqliteDateTime);
        stmt.get.bind(":root", isRoot);
        stmt.get.execute;
    }

    /** Remove all mutants points from the database.
     *
     * This removes all the mutants because of the cascade delete of the
     * tables. But it will keep the mutation statuses and thus the checksums
     * and the status of the code changes.
     *
     * This then mean that when mutations+mutation points are added back they
     * may reconnect with a mutation status.
     */
    void removeAllMutationPoints() @trusted {
        static immutable sql = "DELETE FROM " ~ mutationPointTable;
        db.run(sql);
    }

    /// ditto
    void removeAllFiles() @trusted {
        static immutable sql = "DELETE FROM " ~ filesTable;
        db.run(sql);
    }

    /// Compact the database by running a VACUUM operation
    void vacuum() @trusted {
        db.run("VACUUM");
    }

    /// Returns: the stored scores in ascending order by their `time`.
    MutationScore[] getMutationScoreHistory() @trusted {
        import std.algorithm : sort;

        auto app = appender!(MutationScore[])();
        foreach (r; db.run(select!MutationScoreHistoryTable)) {
            app.put(MutationScore(r.timeStamp, typeof(MutationScore.score)(r.score)));
        }

        return app.data.sort!((a, b) => a.timeStamp < b.timeStamp).array;
    }

    /// Returns: the stored scores in ascending order by their `time`.
    MutationScore[] getMutationFileScoreHistory() @trusted {
        import std.algorithm : sort;

        auto app = appender!(MutationScore[])();
        foreach (r; db.run(select!MutationFileScoreHistoryTable)) {
            app.put(MutationScore(r.timeStamp, typeof(MutationScore.score)(r.score), r.filePath));
        }

        return app.data.sort!((a, b) => a.timeStamp < b.timeStamp).array;
    }

    /// Add a mutation score to the history table.
    void putMutationScore(const MutationScore score) @trusted {
        db.run(insert!MutationScoreHistoryTable, MutationScoreHistoryTable(0,
                score.timeStamp, score.score.get));
    }

    // Add a mutation score for the individual files
    void putMutationFileScore(const MutationScore score) @trusted {
        db.run(insert!MutationFileScoreHistoryTable, MutationFileScoreHistoryTable(0,
                score.timeStamp, score.score.get, score.filePath));
    }

    /// Trim the mutation score history table to only contain the last `keep` scores.
    void trimMutationScore(const long keep) @trusted {
        auto stmt = db.prepare(format!"SELECT count(*) FROM %s"(mutationScoreHistoryTable));
        const sz = stmt.get.execute.oneValue!long;

        if (sz < keep)
            return;

        auto ids = appender!(long[])();
        stmt = db.prepare(format!"SELECT t0.id FROM t0 %s ORDER BY t0.time ASC LIMIT :limit"(
                mutationScoreHistoryTable));
        stmt.get.bind(":limit", sz - keep);
        foreach (a; stmt.get.execute)
            ids.put(a.peek!long(0));

        stmt = db.prepare("DELETE FROM " ~ mutationScoreHistoryTable ~ " WHERE id = :id");
        foreach (a; ids.data) {
            stmt.get.bind(":id", a);
            stmt.get.execute;
            stmt.get.reset;
        }
    }

    /// Returns: the latest/newest timestamp of the tracked SUT or test files.
    Optional!SysTime getLatestTimeStampOfTestOrSut() @trusted {
        import std.algorithm : max;

        auto test = testFileApi.getNewestTestFile;
        auto sut = getNewestFile;

        if (!(test.hasValue || sut.hasValue))
            return none!SysTime;

        return some(max(test.orElse(TestFile.init).timeStamp, sut.orElse(SysTime.init)));
    }

    ref DbDependency dependencyApi() return @trusted {
        dbDependency_ = typeof(return)(&db_, &this);
        return dbDependency_;
    }

    ref DbTestCmd testCmdApi() return @trusted {
        dbTestCmd_ = typeof(return)(&db_);
        return dbTestCmd_;
    }

    ref DbTestCase testCaseApi() return @trusted {
        dbTestCase_ = typeof(return)(&db_);
        return dbTestCase_;
    }

    ref DbMutant mutantApi() return @trusted {
        dbMutant_ = typeof(return)(&db_, &this);
        return dbMutant_;
    }

    ref DbWorklist worklistApi() return @trusted {
        dbWorklist_ = typeof(return)(&db_);
        return dbWorklist_;
    }

    ref DbMemOverload memOverloadApi() return @trusted {
        dbMemOverload_ = typeof(return)(&db_);
        return dbMemOverload_;
    }

    ref DbMarkMutant markMutantApi() return @trusted {
        dbMarkMutant_ = typeof(return)(&db_);
        return dbMarkMutant_;
    }

    ref DbTimeout timeoutApi() return @trusted {
        dbTimeout_ = typeof(return)(&db_);
        return dbTimeout_;
    }

    ref DbCoverage coverageApi() return @trusted {
        dbCoverage_ = typeof(return)(&db_);
        return dbCoverage_;
    }

    ref DbSchema schemaApi() return @trusted {
        dbSchema_ = typeof(return)(&db_, &this);
        return dbSchema_;
    }

    ref DbTestFile testFileApi() return @trusted {
        dbTestFile_ = typeof(return)(&db_);
        return dbTestFile_;
    }

    ref DbMetaData metaDataApi() return @trusted {
        dbMetaData_ = typeof(return)(&db_);
        return dbMetaData_;
    }
}

/** Dependencies between root and those files that should trigger a re-analyze
 * of the root if they are changed.
 */
struct DbDependency {
    private Miniorm* db_;
    private Database* wrapperDb;

    scope ref Miniorm db() return @safe {
        return *db_;
    }

    /// The root must already exist or the whole operation will fail with an sql error.
    void set(const Path path, const DepFile[] deps) @trusted {
        static immutable insertDepSql = "INSERT OR IGNORE INTO " ~ depFileTable
            ~ " (file,checksum0,checksum1)
            VALUES(:file,:cs0,:cs1)
            ON CONFLICT (file) DO UPDATE SET checksum0=:cs0,checksum1=:cs1 WHERE file=:file";

        auto stmt = db.prepare(insertDepSql);
        auto ids = appender!(long[])();
        foreach (a; deps) {
            stmt.get.bind(":file", a.file.toString);
            stmt.get.bind(":cs0", cast(long) a.checksum.c0);
            stmt.get.bind(":cs1", cast(long) a.checksum.c1);
            stmt.get.execute;
            stmt.get.reset;

            // can't use lastInsertRowid because a conflict would not update
            // the ID.
            auto id = getId(a.file);
            if (id.hasValue)
                ids.put(id.orElse(0L));
        }

        static immutable addRelSql = "INSERT OR IGNORE INTO " ~ depRootTable
            ~ " (dep_id,file_id) VALUES(:did, :fid)";
        stmt = db.prepare(addRelSql);
        const fid = () {
            auto a = wrapperDb.getFileId(path);
            if (a.isNull) {
                throw new Exception(
                        "File is not tracked (is missing from the files table in the database) "
                        ~ path);
            }
            return a.get;
        }();

        foreach (id; ids.data) {
            stmt.get.bind(":did", id);
            stmt.get.bind(":fid", fid.get);
            stmt.get.execute;
            stmt.get.reset;
        }
    }

    private Optional!long getId(const Path file) {
        foreach (a; db.run(select!DependencyFileTable.where("file = :file",
                Bind("file")), file.toString)) {
            return some(a.id);
        }
        return none!long;
    }

    /// Returns: all dependencies.
    DepFile[] getAll() @trusted {
        return db.run(select!DependencyFileTable)
            .map!(a => DepFile(Path(a.file), Checksum(a.checksum0, a.checksum1))).array;
    }

    /// Returns: all files that a root is dependent on.
    Path[] get(const Path root) @trusted {
        static immutable sql = format!"SELECT t0.file
            FROM %1$s t0, %2$s t1, %3$s t2
            WHERE
            t0.id = t1.dep_id AND
            t1.file_id = t2.id AND
            t2.path = :file"(depFileTable, depRootTable, filesTable);

        auto stmt = db.prepare(sql);
        stmt.get.bind(":file", root.toString);
        auto app = appender!(Path[])();
        foreach (ref a; stmt.get.execute) {
            app.put(Path(a.peek!string(0)));
        }

        return app.data;
    }

    /// Remove all dependencies that have no relation to a root.
    void cleanup() @trusted {
        db.run(
                "DELETE FROM " ~ depFileTable
                ~ " WHERE id NOT IN (SELECT dep_id FROM " ~ depRootTable ~ ")");
    }

}

struct DbTestCmd {
    import my.hash : Checksum64;

    private Miniorm* db_;

    scope ref Miniorm db() return @safe {
        return *db_;
    }

    void set(string[] testCmds) @trusted {
        if (testCmds.empty)
            return;

        static immutable sql = "INSERT OR IGNORE INTO " ~ testCmdTable ~ "(cmd) VALUES (:cmd)";
        auto stmt = db.prepare(sql);

        foreach (cmd; testCmds) {
            stmt.get.bind(":cmd", cmd);
            stmt.get.execute;
            stmt.get.reset;
        }

        auto new_ = testCmds.toSet;
        auto old = db.run(select!TestCmdTable).map!(a => a.cmd).toSet;

        foreach (a; old.setDifference(new_).toRange)
            db.run(delete_!TestCmdTable.where("cmd=:cmd", Bind("cmd")), a);
    }

    string[] testCmds() @trusted {
        return db.run(select!TestCmdTable).map!(a => a.cmd).array;
    }

    void clearTestCmdToMutant(string testCmd) @trusted {
        static immutable sql = "DELETE FROM " ~ testCmdRelMutantTable
            ~ " t0 INNER JOIN " ~ testCmdTable ~ " t1 ON t0.cmd_id=t1.id WHERE t1.cmd=:cmd";
        auto stmt = db.prepare(sql);
        stmt.get.bind(":cmd", testCmd);
        stmt.get.execute;
    }

    /// Returns: all mutants related to `testCmd`.
    MutationStatusId[] getMutants(string testCmd) @trusted {
        static immutable sql = "SELECT st_id FROM " ~ testCmdRelMutantTable
            ~ " t0, " ~ testCmdTable ~ " t1 WHERE t0.cmd_id=t1.id AND t1.cmd=:cmd";
        auto app = appender!(MutationStatusId[])();
        auto stmt = db.prepare(sql);
        stmt.get.bind(":cmd", testCmd);
        foreach (a; stmt.get.execute)
            app.put(MutationStatusId(a.peek!long(0)));
        return app.data;
    }

    void set(string testCmd, ChecksumTestCmdOriginal cs) @trusted {
        static immutable sql = "INSERT OR REPLACE INTO " ~ testCmdOriginalTable
            ~ " (checksum, cmd_id) " ~ "SELECT :cs,id FROM " ~ testCmdTable ~ " WHERE cmd=:cmd";

        auto stmt = db.prepare(sql);
        stmt.get.bind(":cs", cast(long) cs.get.c0);
        stmt.get.bind(":cmd", testCmd);
        stmt.get.execute;
    }

    string getTestCmd(ChecksumTestCmdOriginal cs) @trusted {
        static immutable sql = "SELECT t1.cmd FROM " ~ testCmdOriginalTable
            ~ " t0, " ~ testCmdTable ~ " t1 WHERE t0.checksum=:cs AND t0.cmd_id=t1.id";
        auto stmt = db.prepare(sql);
        stmt.get.bind(":cs", cs.get.c0);
        foreach (a; stmt.get.execute)
            return a.peek!string(0);
        return null;
    }

    void remove(ChecksumTestCmdOriginal cs) @trusted {
        static immutable sql = "DELETE FROM " ~ testCmdOriginalTable ~ " WHERE checksum = :cs";
        auto stmt = db.prepare(sql);
        stmt.get.bind(":cs", cast(long) cs.get.c0);
        stmt.get.execute;
    }

    Set!Checksum64 original() @trusted {
        static immutable sql = "SELECT checksum FROM " ~ testCmdOriginalTable;

        auto stmt = db.prepare(sql);
        typeof(return) rval;
        foreach (ref r; stmt.get.execute)
            rval.add(Checksum64(cast(ulong) r.peek!long(0)));
        return rval;
    }

    void add(ChecksumTestCmdMutated cs, Mutation.Status status) @trusted {
        static immutable sql = "INSERT OR REPLACE INTO " ~ testCmdMutatedTable
            ~ " (checksum,status,timestamp) VALUES(:cs,:status,:ts)";

        auto stmt = db.prepare(sql);
        stmt.get.bind(":cs", cast(long) cs.get.c0);
        stmt.get.bind(":status", cast(long) status);
        stmt.get.bind(":ts", Clock.currTime.toSqliteDateTime);
        stmt.get.execute;
    }

    /// Trim the saved checksums to only the latest `keep`.
    void trimMutated(const long keep) @trusted {
        auto stmt = db.prepare("SELECT count(*) FROM " ~ testCmdMutatedTable);
        const sz = stmt.get.execute.oneValue!long;
        if (sz < keep)
            return;

        auto ids = appender!(long[])();
        stmt = db.prepare(
                "SELECT checksum FROM " ~ testCmdMutatedTable
                ~ " ORDER BY timestamp ASC LIMIT :limit");
        stmt.get.bind(":limit", sz - keep);
        foreach (a; stmt.get.execute)
            ids.put(a.peek!long(0));

        stmt = db.prepare("DELETE FROM " ~ testCmdMutatedTable ~ " WHERE checksum = :cs");
        foreach (a; ids.data) {
            stmt.get.bind(":cs", a);
            stmt.get.execute;
            stmt.get.reset;
        }
    }

    Mutation.Status[Checksum64] mutated() @trusted {
        static immutable sql = "SELECT checksum,status FROM " ~ testCmdMutatedTable;

        auto stmt = db.prepare(sql);
        typeof(return) rval;
        foreach (ref r; stmt.get.execute)
            rval[Checksum64(cast(ulong) r.peek!long(0))] = r.peek!long(1).to!(Mutation.Status);
        return rval;
    }

    /// Returns: the stored runtimes in ascending order by their `timeStamp`.
    TestCmdRuntime[] getTestCmdRuntimes() @trusted {
        import std.algorithm : sort;

        auto app = appender!(TestCmdRuntime[])();
        foreach (r; db.run(select!RuntimeHistoryTable)) {
            app.put(TestCmdRuntime(r.timeStamp, r.timeMs.dur!"msecs"));
        }

        return app.data.sort!((a, b) => a.timeStamp < b.timeStamp).array;
    }

    /// Drop all currently stored runtimes and replaces with `runtime`.
    void setTestCmdRuntimes(const TestCmdRuntime[] runtimes) @trusted {
        db.run("DELETE FROM " ~ runtimeHistoryTable);
        db.run(insertOrReplace!RuntimeHistoryTable,
                runtimes.enumerate.map!(a => RuntimeHistoryTable(a.index,
                    a.value.timeStamp, a.value.runtime.total!"msecs")));
    }
}

struct DbTestCase {
    private Miniorm* db_;

    scope ref Miniorm db() return @safe {
        return *db_;
    }

    /** Add a link between the mutation and what test case killed it.
     *
     * Params:
     *  id = ?
     *  tcs = test cases to add
     */
    void updateMutationTestCases(const MutationId id, const(TestCase)[] tcs) @trusted {
        if (tcs.length == 0)
            return;

        immutable statusId = () {
            static immutable st_id_for_mutation_q = "SELECT st_id FROM "
                ~ mutationTable ~ " WHERE id=:id";
            auto stmt = db.prepare(st_id_for_mutation_q);
            stmt.get.bind(":id", cast(long) id);
            return stmt.get.execute.oneValue!long;
        }();
        updateMutationTestCases(MutationStatusId(statusId), tcs);
    }

    /** Add a link between the mutation and what test case killed it.
     *
     * Params:
     *  id = ?
     *  tcs = test cases to add
     */
    void updateMutationTestCases(const MutationStatusId statusId, const(TestCase)[] tcs) @trusted {
        if (tcs.length == 0)
            return;

        try {
            static immutable remove_old_sql = "DELETE FROM "
                ~ killedTestCaseTable ~ " WHERE st_id=:id";
            auto stmt = db.prepare(remove_old_sql);
            stmt.get.bind(":id", statusId.get);
            stmt.get.execute;
        } catch (Exception e) {
        }

        static immutable add_if_non_exist_tc_sql = "INSERT OR IGNORE INTO " ~ allTestCaseTable
            ~ " (name,is_new) SELECT :name1,1 WHERE NOT EXISTS (SELECT * FROM "
            ~ allTestCaseTable ~ " WHERE name = :name2)";
        auto stmt_insert_tc = db.prepare(add_if_non_exist_tc_sql);

        static immutable add_new_sql = "INSERT OR IGNORE INTO " ~ killedTestCaseTable
            ~ " (st_id, tc_id, location) SELECT :st_id,t1.id,:loc FROM "
            ~ allTestCaseTable ~ " t1 WHERE t1.name = :tc";
        auto stmt_insert = db.prepare(add_new_sql);
        foreach (const tc; tcs) {
            try {
                stmt_insert_tc.get.reset;
                stmt_insert_tc.get.bind(":name1", tc.name);
                stmt_insert_tc.get.bind(":name2", tc.name);
                stmt_insert_tc.get.execute;

                stmt_insert.get.reset;
                stmt_insert.get.bind(":st_id", statusId.get);
                stmt_insert.get.bind(":loc", tc.location);
                stmt_insert.get.bind(":tc", tc.name);
                stmt_insert.get.execute;
            } catch (Exception e) {
                logger.warning(e.msg);
            }
        }
    }

    /** Set detected test cases.
     *
     * This will replace those that where previously stored.
     *
     * Returns: ID of affected mutation statuses.
     */
    MutationStatusId[] setDetectedTestCases(const(TestCase)[] tcs) @trusted {
        if (tcs.empty)
            return null;

        auto ids = appender!(MutationStatusId[])();

        static immutable tmp_name = "tmp_new_tc_" ~ __LINE__.to!string;
        internalAddDetectedTestCases(tcs, tmp_name);

        static immutable mut_st_id = format!"SELECT DISTINCT t1.st_id
            FROM %s t0, %s t1
            WHERE
            t0.name NOT IN (SELECT name FROM %s) AND
            t0.id = t1.tc_id"(allTestCaseTable, killedTestCaseTable, tmp_name);
        auto stmt = db.prepare(mut_st_id);
        foreach (res; stmt.get.execute) {
            ids.put(res.peek!long(0).MutationStatusId);
        }

        static immutable remove_old_sql = "DELETE FROM " ~ allTestCaseTable
            ~ " WHERE name NOT IN (SELECT name FROM " ~ tmp_name ~ ")";
        db.run(remove_old_sql);

        db.run("DROP TABLE " ~ tmp_name);

        return ids.data;
    }

    /** Add test cases to those that have been detected.
     *
     * They will be added if they are unique.
     */
    void addDetectedTestCases(const(TestCase)[] tcs) @trusted {
        if (tcs.length == 0)
            return;

        static immutable tmp_name = "tmp_new_tc_" ~ __LINE__.to!string;
        internalAddDetectedTestCases(tcs, tmp_name);
        db.run(format!"DROP TABLE %s"(tmp_name));
    }

    /// ditto.
    private void internalAddDetectedTestCases(const(TestCase)[] tcs, string tmp_tbl) @trusted {
        db.run("CREATE TEMP TABLE " ~ tmp_tbl ~ " (id INTEGER PRIMARY KEY, name TEXT NOT NULL)");

        const add_tc_sql = "INSERT OR IGNORE INTO " ~ tmp_tbl ~ " (name) VALUES(:name)";
        auto insert_s = db.prepare(add_tc_sql);
        foreach (tc; tcs.filter!(a => !a.name.empty)) {
            insert_s.get.bind(":name", tc.name);
            insert_s.get.execute;
            insert_s.get.reset;
        }

        // https://stackoverflow.com/questions/2686254/how-to-select-all-records-from-one-table-that-do-not-exist-in-another-table
        //Q: What is happening here?
        //
        //A: Conceptually, we select all rows from table1 and for each row we
        //attempt to find a row in table2 with the same value for the name
        //column.  If there is no such row, we just leave the table2 portion of
        //our result empty for that row. Then we constrain our selection by
        //picking only those rows in the result where the matching row does not
        //exist. Finally, We ignore all fields from our result except for the
        //name column (the one we are sure that exists, from table1).
        //
        //While it may not be the most performant method possible in all cases,
        //it should work in basically every database engine ever that attempts
        //to implement ANSI 92 SQL
        const add_missing_sql = format!"INSERT OR IGNORE INTO %s (name,is_new) SELECT t1.name,1 FROM %s t1 LEFT JOIN %s t2 ON t2.name = t1.name WHERE t2.name IS NULL"(
                allTestCaseTable, tmp_tbl, allTestCaseTable);
        db.run(add_missing_sql);
    }

    /// Returns: detected test cases.
    TestCase[] getDetectedTestCases() @trusted {
        auto rval = appender!(TestCase[])();
        db.run(select!AllTestCaseTbl).map!(a => TestCase(a.name)).copy(rval);
        return rval.data;
    }

    /// Returns: detected test cases.
    TestCaseId[] getDetectedTestCaseIds() @trusted {
        auto rval = appender!(TestCaseId[])();
        db.run(select!AllTestCaseTbl).map!(a => TestCaseId(a.id)).copy(rval);
        return rval.data;
    }

    /// Returns: test cases that has killed zero mutants.
    TestCase[] getTestCasesWithZeroKills() @trusted {
        static immutable sql = format("SELECT t1.name FROM %s t1 WHERE t1.id NOT IN (SELECT tc_id FROM %s)",
                allTestCaseTable, killedTestCaseTable);

        auto rval = appender!(TestCase[])();
        auto stmt = db.prepare(sql);
        foreach (a; stmt.get.execute)
            rval.put(TestCase(a.peek!string(0)));

        return rval.data;
    }

    /** Guarantees that the there are no duplications of `TestCaseId`.
     *
     * Returns: test cases that has killed at least one mutant.
     */
    TestCaseId[] getTestCasesWithAtLeastOneKill(const Mutation.Kind[] kinds) @trusted {
        const sql = format!"SELECT DISTINCT t1.id
            FROM %s t1, %s t2, %s t3
            WHERE
            t1.id = t2.tc_id AND
            t2.st_id == t3.st_id AND
            t3.kind IN (%(%s,%))"(allTestCaseTable, killedTestCaseTable,
                mutationTable, kinds.map!(a => cast(int) a));

        auto rval = appender!(TestCaseId[])();
        auto stmt = db.prepare(sql);
        foreach (a; stmt.get.execute)
            rval.put(TestCaseId(a.peek!long(0)));

        return rval.data;
    }

    /// Returns: the name of the test case.
    string getTestCaseName(const TestCaseId id) @trusted {
        static immutable sql = format!"SELECT name FROM %s WHERE id = :id"(allTestCaseTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", cast(long) id);
        auto res = stmt.get.execute;
        return res.oneValue!string;
    }

    /// Returns: stats about the test case.
    TestCaseInfo getTestCaseInfo(const TestCaseId tcId, const Mutation.Kind[] kinds) @trusted {
        const sql = format("SELECT sum(ctime),sum(ttime),count(*)
            FROM (
            SELECT sum(t2.compile_time_ms) ctime,sum(t2.test_time_ms) ttime
            FROM %s t1, %s t2, %s t3
            WHERE
            :id = t1.tc_id AND
            t1.st_id = t2.id AND
            t1.st_id = t3.st_id AND
            t3.kind IN (%(%s,%))
            GROUP BY t1.st_id)", killedTestCaseTable, mutationStatusTable,
                mutationTable, kinds.map!(a => cast(int) a));
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", tcId.get);

        typeof(return) rval;
        foreach (a; stmt.get.execute) {
            rval = TestCaseInfo(MutantTimeProfile(a.peek!long(0).dur!"msecs",
                    a.peek!long(1).dur!"msecs"), a.peek!long(2));
        }
        return rval;
    }

    Nullable!TestCaseInfo getTestCaseInfo(const TestCase tc, const Mutation.Kind[] kinds) @safe {
        typeof(return) rval;

        auto id = getTestCaseId(tc);
        if (!id.isNull)
            rval = getTestCaseInfo(id.get, kinds);

        return rval;
    }

    /// Returns: all test cases for the file and the mutants they killed.
    TestCaseInfo2[] getAllTestCaseInfo2(const FileId file, const Mutation.Kind[] kinds) @trusted {
        // row of test case name and mutation id.
        const sql = format("SELECT t0.name,t3.id
            FROM %s t0, %s t1, %s t2, %s t3, %s t4
            WHERE
            t0.id = t1.tc_id AND
            t1.st_id = t2.id AND
            t2.id = t3.st_id AND
            t4.id = :file_id AND
            t3.kind IN (%(%s,%))", allTestCaseTable, killedTestCaseTable,
                mutationStatusTable, mutationTable, filesTable, kinds.map!(a => cast(int) a));
        auto stmt = db.prepare(sql);
        stmt.get.bind(":file_id", cast(long) file);

        MutationId[][string] data;
        foreach (row; stmt.get.execute) {
            const name = row.peek!string(0);
            auto id = MutationId(row.peek!long(1));
            data.update(name, () => [id], (ref MutationId[] a) { a ~= id; });
        }

        auto app = appender!(TestCaseInfo2[])();
        data.byKeyValue.map!(a => TestCaseInfo2(TestCase(a.key), a.value)).copy(app);
        return app.data;
    }

    /// Returns: the test case.
    Nullable!TestCase getTestCase(const TestCaseId id) @trusted {
        static immutable sql = format!"SELECT name FROM %s WHERE id = :id"(allTestCaseTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", cast(long) id);

        typeof(return) rval;
        foreach (res; stmt.get.execute) {
            rval = TestCase(res.peek!string(0));
        }
        return rval;
    }

    /// Returns: the test case id.
    Nullable!TestCaseId getTestCaseId(const TestCase tc) @trusted {
        static immutable sql = format!"SELECT id FROM %s WHERE name = :name"(allTestCaseTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":name", tc.name);

        typeof(return) rval;
        foreach (res; stmt.get.execute) {
            rval = TestCaseId(res.peek!long(0));
        }
        return rval;
    }

    /// The mutation ids are guaranteed to be sorted.
    /// Returns: the mutants the test case killed.
    MutationId[] getTestCaseMutantKills(const TestCaseId id, const Mutation.Kind[] kinds) @trusted {
        immutable sql = format!"SELECT t2.id
            FROM %s t1, %s t2
            WHERE
            t1.tc_id = :tid AND
            t1.st_id = t2.st_id AND
            t2.kind IN (%(%s,%))
            GROUP BY t2.st_id
            ORDER BY t2.id"(killedTestCaseTable, mutationTable, kinds.map!(a => cast(int) a));

        auto rval = appender!(MutationId[])();
        auto stmt = db.prepare(sql);
        stmt.get.bind(":tid", cast(long) id);
        foreach (a; stmt.get.execute)
            rval.put(MutationId(a.peek!long(0)));

        return rval.data;
    }

    /// Returns: test cases that killed the mutant.
    TestCase[] getTestCases(const MutationId id) @trusted {
        Appender!(TestCase[]) rval;

        static immutable get_test_cases_sql = format!"SELECT t1.name,t2.location
            FROM %s t1, %s t2, %s t3
            WHERE
            t3.id = :id AND
            t3.st_id = t2.st_id AND
            t2.tc_id = t1.id"(allTestCaseTable, killedTestCaseTable, mutationTable);
        auto stmt = db.prepare(get_test_cases_sql);
        stmt.get.bind(":id", cast(long) id);
        foreach (a; stmt.get.execute)
            rval.put(TestCase(a.peek!string(0), a.peek!string(1)));

        return rval.data;
    }

    /// Returns: if the mutant have any test cases recorded that killed it
    bool hasTestCases(const MutationStatusId id) @trusted {
        static immutable sql = format!"SELECT count(*) FROM %s t0 WHERE t0.st_id = :id"(
                killedTestCaseTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", id.get);
        foreach (a; stmt.get.execute) {
            return a.peek!long(0) != 0;
        }
        return false;
    }

    /** Returns: number of test cases
     */
    long getNumOfTestCases() @trusted {
        static immutable num_test_cases_sql = format!"SELECT count(*) FROM %s"(allTestCaseTable);
        return db.execute(num_test_cases_sql).oneValue!long;
    }

    void removeTestCase(const TestCaseId id) @trusted {
        auto stmt = db.prepare("DELETE FROM " ~ allTestCaseTable ~ " WHERE id=:id");
        stmt.get.bind(":id", cast(long) id);
        stmt.get.execute;
    }

    /// Change the status of all mutants that the test case has killed to unknown.
    void resetTestCaseId(const TestCaseId id) @trusted {
        {
            static immutable sql = format!"UPDATE %1$s SET status=0 WHERE id IN (SELECT t1.id FROM %2$s t0, %1$s t1 WHERE t0.tc_id = :id AND t0.st_id = t1.id)"(
                    mutationStatusTable, killedTestCaseTable);
            auto stmt = db.prepare(sql);
            stmt.get.bind(":id", cast(long) id);
            stmt.get.execute;
        }
        {
            static immutable sql2 = "DELETE FROM " ~ killedTestCaseTable ~ " WHERE tc_id = :id";
            auto stmt = db.prepare(sql2);
            stmt.get.bind(":id", cast(long) id);
            stmt.get.execute;
        }
    }

    /// Returns: mutants killed by the test case.
    MutationStatusId[] testCaseKilledSrcMutants(const Mutation.Kind[] kinds, const TestCaseId id) @trusted {
        const sql = format("SELECT t1.id
            FROM %s t0, %s t1, %s t3
            WHERE
            t0.st_id = t1.id AND
            t1.status = :st AND
            t0.kind IN (%(%s,%)) AND
            t3.tc_id = :id AND
            t3.st_id = t1.id
            GROUP BY t1.id", mutationTable, mutationStatusTable,
                killedTestCaseTable, kinds.map!(a => cast(int) a));

        auto stmt = db.prepare(sql);
        stmt.get.bind(":st", cast(long) Mutation.Status.killed);
        stmt.get.bind(":id", id.get);

        auto app = appender!(MutationStatusId[])();
        foreach (res; stmt.get.execute)
            app.put(MutationStatusId(res.peek!long(0)));

        return app.data;
    }

    MutationStatusId[] testCaseKilledSrcMutants(const Mutation.Kind[] kinds, const TestCase tc) @safe {
        auto id = getTestCaseId(tc);
        if (id.isNull)
            return null;
        return testCaseKilledSrcMutants(kinds, id.get);
    }

    /// Returns: mutants at mutations points that the test case has killed mutants at.
    alias testCaseMutationPointAliveSrcMutants = testCaseCountSrcMutants!([
        Mutation.Status.alive
    ]);
    /// ditto
    alias testCaseMutationPointTimeoutSrcMutants = testCaseCountSrcMutants!(
            [Mutation.Status.timeout]);
    /// ditto
    alias testCaseMutationPointKilledSrcMutants = testCaseCountSrcMutants!([
        Mutation.Status.killed
    ]);
    /// ditto
    alias testCaseMutationPointUnknownSrcMutants = testCaseCountSrcMutants!(
            [Mutation.Status.unknown]);
    /// ditto
    alias testCaseMutationPointKilledByCompilerSrcMutants = testCaseCountSrcMutants!(
            [Mutation.Status.killedByCompiler]);
    /// ditto
    alias testCaseMutationPointTotalSrcMutants = testCaseCountSrcMutants!(
            [
        Mutation.Status.alive, Mutation.Status.killed, Mutation.Status.timeout
    ]);

    private MutationStatusId[] testCaseCountSrcMutants(int[] status)(
            const Mutation.Kind[] kinds, TestCase tc) @trusted {
        const query = format("
            SELECT t1.id
            FROM %s t0, %s t1
            WHERE
            t0.mp_id IN (SELECT t1.id
                      FROM %s t0,%s t1, %s t2, %s t3
                      WHERE
                      t0.mp_id = t1.id AND
                      t2.name = :name AND
                      t2.id = t3.tc_id AND
                      t3.st_id = t0.st_id
                      )
            AND
            t0.st_id = t1.id AND
            t1.status IN (%(%s,%)) AND
            t0.kind IN (%(%s,%))
            GROUP BY t1.id", mutationTable, mutationStatusTable, mutationTable, mutationPointTable,
                allTestCaseTable, killedTestCaseTable, status, kinds.map!(a => cast(int) a));

        auto stmt = db.prepare(query);
        stmt.get.bind(":name", tc.name);

        auto app = appender!(MutationStatusId[])();
        foreach (res; stmt.get.execute)
            app.put(MutationStatusId(res.peek!long(0)));

        return app.data;
    }

    TestCaseId[] getNewTestCases() @trusted {
        auto rval = appender!(TestCaseId[])();
        db.run(select!AllTestCaseTbl).filter!(a => a.isNew)
            .map!(a => TestCaseId(a.id))
            .copy(rval);
        return rval.data;
    }

    void removeNewTestCaseTag() @trusted {
        immutable sql = "UPDATE " ~ allTestCaseTable ~ " SET is_new=0";
        auto stmt = db.prepare(sql);
        stmt.get.execute;
    }
}

struct DbMutant {
    private Miniorm* db_;
    private Database* wrapperDb;

    scope ref Miniorm db() return @safe {
        return *db_;
    }

    bool exists(MutationStatusId id) {
        static immutable s = format!"SELECT COUNT(*) FROM %s WHERE id=:id LIMIT 1"(
                mutationStatusTable);
        auto stmt = db.prepare(s);
        stmt.get.bind(":id", cast(long) id);
        auto res = stmt.get.execute;
        return res.oneValue!long == 0;
    }

    /** Update the status of a mutant.
     *
     * Params:
     *  id = ID of the mutant
     *  st = status to broadcast
     *  d = time spent on veryfing the mutant
     *  tcs = test cases that killed the mutant
     *  counter = how to act with the counter
     */
    void update(const MutationId id, const Mutation.Status st,
            const ExitStatus ecode, const MutantTimeProfile p, const(TestCase)[] tcs) @trusted {
        static immutable sql = "UPDATE %s SET
            status=:st,compile_time_ms=:compile,test_time_ms=:test,update_ts=:update_ts
            WHERE id IN (SELECT st_id FROM %s WHERE id = :id)";

        auto stmt = db.prepare(format!sql(mutationStatusTable, mutationTable));
        stmt.get.bind(":st", cast(long) st);
        stmt.get.bind(":id", id.get);
        stmt.get.bind(":compile", p.compile.total!"msecs");
        stmt.get.bind(":test", p.test.total!"msecs");
        stmt.get.bind(":update_ts", Clock.currTime.toSqliteDateTime);
        stmt.get.execute;

        wrapperDb.testCaseApi.updateMutationTestCases(id, tcs);
    }

    /** Update the status of a mutant.
     *
     * Params:
     *  id = ID of the mutant
     *  st = status to broadcast
     *  d = time spent on veryfing the mutant
     *  tcs = test cases that killed the mutant
     *  counter = how to act with the counter
     */
    void update(const MutationStatusId id, const Mutation.Status st,
            const ExitStatus ecode, const MutantTimeProfile p) @trusted {
        static immutable sql = "UPDATE " ~ mutationStatusTable ~ " SET
            status=:st,compile_time_ms=:compile,test_time_ms=:test,update_ts=:update_ts
            WHERE id = :id";

        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", id.get);
        stmt.get.bind(":st", cast(long) st);
        stmt.get.bind(":compile", p.compile.total!"msecs");
        stmt.get.bind(":test", p.test.total!"msecs");
        stmt.get.bind(":update_ts", Clock.currTime.toSqliteDateTime);
        stmt.get.execute;
    }

    /// Update the time used to test the mutant.
    void update(const MutationStatusId id, const MutantTimeProfile p) @trusted {
        static immutable sql = "UPDATE " ~ mutationStatusTable
            ~ " SET compile_time_ms=:compile,test_time_ms=:test WHERE id = :id";
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", id.get);
        stmt.get.bind(":compile", p.compile.total!"msecs");
        stmt.get.bind(":test", p.test.total!"msecs");
        stmt.get.execute;
    }

    /** Update the status of a mutant.
     *
     * Params:
     *  id = mutation status ID
     *  st = new status
     *  update_ts = if the update timestamp should be updated.
     */
    void update(const MutationStatusId id, const Mutation.Status st,
            const ExitStatus ecode, Flag!"updateTs" update_ts = No.updateTs) @trusted {
        auto stmt = () {
            static immutable sql1 = "UPDATE " ~ mutationStatusTable
                ~ " SET status=:st,exit_code=:ecode,update_ts=:update_ts WHERE id=:id";
            static immutable sql2 = "UPDATE " ~ mutationStatusTable
                ~ " SET status=:st,exit_code=:ecode WHERE id=:id";

            if (update_ts) {
                const ts = Clock.currTime.toSqliteDateTime;
                auto s = db.prepare(sql1);
                s.get.bind(":update_ts", ts);
                return s;
            }
            return db.prepare(sql2);
        }();
        stmt.get.bind(":st", st.to!long);
        stmt.get.bind(":id", id.to!long);
        stmt.get.bind(":ecode", ecode.get);
        stmt.get.execute;
    }

    void relate(const MutationStatusId id, const string testCmd) @trusted {
        static immutable sql = "INSERT OR IGNORE INTO " ~ testCmdRelMutantTable
            ~ " (cmd_id, st_id) " ~ "SELECT id,:st_id FROM " ~ testCmdTable ~ " WHERE cmd=:cmd";
        auto stmt = db.prepare(sql);
        stmt.get.bind(":st_id", cast(long) id);
        stmt.get.bind(":cmd", testCmd);
        stmt.get.execute;
    }

    /// Returns: all mutants and how many test cases that have killed them.
    long[] getAllTestCaseKills() @trusted {
        static immutable sql = "SELECT (SELECT count(*) FROM " ~ killedTestCaseTable
            ~ " WHERE t0.id=st_id) as vc_cnt FROM " ~ mutationStatusTable ~ " t0";
        auto stmt = db.prepare(sql);

        auto app = appender!(long[])();
        foreach (res; stmt.get.execute)
            app.put(res.peek!long(0));

        return app.data;
    }

    /// Returns: all mutation status IDs.
    MutationStatusId[] getAllMutationStatus() @trusted {
        static immutable sql = "SELECT id FROM " ~ mutationStatusTable;

        auto app = appender!(MutationStatusId[])();
        auto stmt = db.prepare(sql);
        foreach (r; stmt.get.execute)
            app.put(MutationStatusId(r.peek!long(0)));
        return app.data;
    }

    // TODO: change to my.optional
    Nullable!(Mutation.Status) getMutationStatus(const MutationStatusId id) @trusted {
        static immutable sql = format!"SELECT status FROM %s WHERE id=:id"(mutationStatusTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", id.get);

        typeof(return) rval;
        foreach (a; stmt.get.execute) {
            rval = cast(Mutation.Status) a.peek!long(0);
        }
        return rval;
    }

    Nullable!MutationEntry getMutation(const MutationId id) @trusted {
        import dextool.plugin.mutate.backend.type;

        typeof(return) rval;

        static immutable get_mut_sql = format("SELECT
            t0.id,
            t0.kind,
            t3.compile_time_ms,
            t3.test_time_ms,
            t1.offset_begin,
            t1.offset_end,
            t1.line,
            t1.column,
            t2.path,
            t2.lang
            FROM %s t0,%s t1,%s t2,%s t3
            WHERE
            t0.id = :id AND
            t0.mp_id = t1.id AND
            t1.file_id = t2.id AND
            t3.id = t0.st_id
            ", mutationTable, mutationPointTable, filesTable, mutationStatusTable);

        auto stmt = db.prepare(get_mut_sql);
        stmt.get.bind(":id", cast(long) id);
        auto res = stmt.get.execute;

        if (res.empty)
            return rval;

        auto v = res.front;

        auto mp = MutationPoint(Offset(v.peek!uint(4), v.peek!uint(5)));
        mp.mutations = [Mutation(v.peek!long(1).to!(Mutation.Kind))];
        auto pkey = MutationId(v.peek!long(0));
        auto file = Path(v.peek!string(8));
        auto sloc = SourceLoc(v.peek!uint(6), v.peek!uint(7));
        auto lang = v.peek!long(9).to!Language;

        rval = MutationEntry(pkey, file, sloc, mp,
                MutantTimeProfile(v.peek!long(2).dur!"msecs", v.peek!long(3).dur!"msecs"), lang);

        return rval;
    }

    MutantMetaData getMutantationMetaData(const MutationId id) @trusted {
        auto rval = MutantMetaData(id);
        foreach (res; db.run(select!NomutDataTbl.where("mut_id = :mutid", Bind("mutid")), id.get)) {
            rval.set(NoMut(res.tag, res.comment));
        }
        return rval;
    }

    // TODO: fix spelling error
    // TODO: this is a bit inefficient. it should use a callback iterator
    MutantMetaData[] getMutantationMetaData(const Mutation.Kind[] kinds, const Mutation
            .Status status) @trusted {
        const sql = format!"SELECT DISTINCT t.mut_id, t.tag, t.comment
        FROM %s t, %s t1, %s t2
        WHERE
        t.mut_id = t1.id AND
        t1.st_id = t2.id AND
        t2.status = :status AND
        t1.kind IN (%(%s,%))
        ORDER BY
        t.mut_id"(nomutDataTable, mutationTable, mutationStatusTable,
                kinds.map!(a => cast(long) a));
        auto stmt = db.prepare(sql);
        stmt.get.bind(":status", cast(long) status);

        auto app = appender!(MutantMetaData[])();
        foreach (res; stmt.get.execute) {
            app.put(MutantMetaData(MutationId(res.peek!long(0)),
                    MutantAttr(NoMut(res.peek!string(1), res.peek!string(2)))));
        }
        return app.data;
    }

    Nullable!Path getPath(const MutationId id) @trusted {
        static immutable get_path_sql = format("SELECT t2.path
            FROM
            %s t0, %s t1, %s t2
            WHERE
            t0.id = :id AND
            t0.mp_id = t1.id AND
            t1.file_id = t2.id
            ", mutationTable, mutationPointTable, filesTable);

        auto stmt = db.prepare(get_path_sql);
        stmt.get.bind(":id", cast(long) id);
        auto res = stmt.get.execute;

        typeof(return) rval;
        if (!res.empty)
            rval = Path(res.front.peek!string(0));
        return rval;
    }

    Nullable!Path getPath(const MutationStatusId id) @trusted {
        static immutable get_path_sql = format("SELECT t2.path
            FROM
            %s t0, %s t1, %s t2
            WHERE
            t0.st_id = :id AND t0.mp_id = t1.id AND t1.file_id = t2.id
            ", mutationTable, mutationPointTable, filesTable);

        auto stmt = db.prepare(get_path_sql);
        stmt.get.bind(":id", id.get);
        auto res = stmt.get.execute;

        typeof(return) rval;
        if (!res.empty)
            rval = Path(res.front.peek!string(0));
        return rval;
    }

    /// Returns: the mutants that are connected to the mutation statuses.
    MutantInfo[] getMutantsInfo(const Mutation.Kind[] kinds, const(MutationStatusId)[] id) @trusted {
        const get_mutid_sql = format("SELECT t0.id,t2.status,t2.exit_code,t0.kind,t1.line,t1.column
            FROM %s t0,%s t1, %s t2
            WHERE
            t0.st_id IN (%(%s,%)) AND
            t0.st_id = t2.id AND
            t0.kind IN (%(%s,%)) AND
            t0.mp_id = t1.id", mutationTable, mutationPointTable,
                mutationStatusTable, id.map!(a => a.get), kinds.map!(a => cast(int) a));
        auto stmt = db.prepare(get_mutid_sql);

        auto app = appender!(MutantInfo[])();
        foreach (res; stmt.get.execute) {
            app.put(MutantInfo(MutationId(res.peek!long(0)), res.peek!long(1)
                    .to!(Mutation.Status), res.peek!int(2).ExitStatus,
                    res.peek!long(3).to!(Mutation.Kind),
                    SourceLoc(res.peek!uint(4), res.peek!uint(5))));
        }

        return app.data;
    }

    /// Returns: the mutants that are connected to the mutation statuses.
    Optional!MutantInfo2 getMutantInfo(const MutationStatusId id) @trusted {
        static const sql = format(
                "SELECT t0.id,t2.status,t2.exit_code,t3.path,t1.line,t1.column,t2.prio,t2.update_ts,
            (SELECT count(*) FROM %s WHERE st_id = :id) as vc_cnt
            FROM %s t0,%s t1, %s t2, %s t3
            WHERE
            t2.id = :id AND
            t0.st_id = :id AND
            t0.mp_id = t1.id AND
            t1.file_id = t3.id
            ", killedTestCaseTable, mutationTable, mutationPointTable,
                mutationStatusTable, filesTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", id.get);

        foreach (res; stmt.get.execute) {
            // dfmt off
            return MutantInfo2(
                res.peek!long(0).MutationId,
                res.peek!long(1).to!(Mutation.Status),
                res.peek!int(2).to!ExitStatus,
                res.peek!string(3).Path,
                SourceLoc(res.peek!uint(4), res.peek!uint(5)),
                res.peek!long(6).MutantPrio,
                res.peek!string(7).fromSqLiteDateTime,
                res.peek!int(8)).some;
            // dfmt on
        }

        return none!MutantInfo2;
    }

    /// Returns: the mutants that are connected to the mutation statuses.
    MutationId[] getMutationIds(const(Mutation.Kind)[] kinds, const(MutationStatusId)[] id) @trusted {
        if (id.length == 0)
            return null;

        const get_mutid_sql = format!"SELECT id FROM %s t0
            WHERE
            t0.st_id IN (%(%s,%)) AND
            t0.kind IN (%(%s,%))"(mutationTable, id.map!(a => cast(long) a),
                kinds.map!(a => cast(int) a));
        auto stmt = db.prepare(get_mutid_sql);

        auto app = appender!(MutationId[])();
        foreach (res; stmt.get.execute)
            app.put(MutationId(res.peek!long(0)));
        return app.data;
    }

    Nullable!MutationId getMutationId(const MutationStatusId id) @trusted {
        static immutable sql = format!"SELECT id FROM %s WHERE st_id=:st_id"(mutationTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":st_id", id.get);

        typeof(return) rval;
        foreach (res; stmt.get.execute) {
            rval = res.peek!long(0).MutationId;
            break;
        }
        return rval;
    }

    MutationStatus getMutationStatus2(const MutationStatusId id) @trusted {
        const sql = format("SELECT t0.id,t0.status,t0.prio,t0.update_ts,t0.added_ts
            FROM %s t0
            WHERE
            t0.update_ts IS NOT NULL AND
            t0.id = :id", mutationStatusTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", id.get);

        foreach (res; stmt.get.execute) {
            auto added = () {
                auto raw = res.peek!string(4);
                if (raw.length == 0)
                    return Nullable!SysTime();
                return Nullable!SysTime(raw.fromSqLiteDateTime);
            }();

            return MutationStatus(MutationStatusId(res.peek!long(0)),
                    res.peek!long(1).to!(Mutation.Status), res.peek!long(2)
                    .MutantPrio, res.peek!string(3).fromSqLiteDateTime, added,);
        }

        return MutationStatus.init;
    }

    Nullable!MutationStatusId getMutationStatusId(const MutationId id) @trusted {
        static immutable sql = format!"SELECT st_id FROM %s WHERE id=:id"(mutationTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", cast(long) id);

        typeof(return) rval;
        foreach (res; stmt.get.execute) {
            rval = MutationStatusId(res.peek!long(0));
        }
        return rval;
    }

    Nullable!MutationStatusId getMutationStatusId(const Checksum cs) @trusted {
        static immutable sql = format!"SELECT id FROM %s WHERE checksum0=:cs0 AND checksum1=:cs1"(
                mutationStatusTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":cs0", cast(long) cs.c0);
        stmt.get.bind(":cs1", cast(long) cs.c1);

        typeof(return) rval;
        foreach (res; stmt.get.execute) {
            rval = MutationStatusId(res.peek!long(0));
        }
        return rval;
    }

    // TODO: maybe this need to return the exit code too?
    // Returns: the status of the mutant
    Nullable!(Mutation.Status) getMutationStatus(const MutationId id) @trusted {
        auto s = format!"SELECT status FROM %s WHERE id IN (SELECT st_id FROM %s WHERE id=:mut_id)"(
                mutationStatusTable, mutationTable);
        auto stmt = db.prepare(s);
        stmt.get.bind(":mut_id", cast(long) id);
        typeof(return) rval;
        foreach (res; stmt.get.execute)
            rval = res.peek!long(0).to!(Mutation.Status);
        return rval;
    }

    /// Returns: the mutants in the file at the line.
    MutationStatusId[] getMutationsOnLine(const(Mutation.Kind)[] kinds, FileId fid, SourceLoc sloc) @trusted {
        // TODO: should it also be line_end?
        const sql = format("SELECT DISTINCT t0.id FROM %s t0, %s t1, %s t2
                    WHERE
                    t1.st_id = t0.id AND
                    t1.kind IN (%(%s,%)) AND
                    t1.mp_id = t2.id AND
                    t2.file_id = :fid AND
                    (:line BETWEEN t2.line AND t2.line_end)", mutationStatusTable,
                mutationTable, mutationPointTable, kinds.map!(a => cast(int) a));
        auto stmt = db.prepare(sql);
        stmt.get.bind(":fid", cast(long) fid);
        stmt.get.bind(":line", sloc.line);

        auto app = appender!(typeof(return))();
        foreach (res; stmt.get.execute)
            app.put(MutationStatusId(res.peek!long(0)));
        return app.data;
    }

    /// Returns: the `nr` mutants that where the longst since they where tested.
    MutationStatusTime[] getOldestMutants(const(Mutation.Kind)[] kinds,
            const long nr, const Mutation.Status[] status) @trusted {
        const sql = format("SELECT t0.id,t0.update_ts FROM %s t0, %s t1
                    WHERE
                    t0.update_ts IS NOT NULL AND
                    t1.st_id = t0.id AND
                    t1.kind IN (%(%s,%)) AND
                    t0.status IN (%(%s,%))
                    ORDER BY datetime(t0.update_ts) ASC LIMIT :limit", mutationStatusTable,
                mutationTable, kinds.map!(a => cast(int) a), status.map!(a => cast(int) a));
        auto stmt = db.prepare(sql);
        stmt.get.bind(":limit", nr);

        auto app = appender!(MutationStatusTime[])();
        foreach (res; stmt.get.execute)
            app.put(MutationStatusTime(MutationStatusId(res.peek!long(0)),
                    res.peek!string(1).fromSqLiteDateTime));
        return app.data;
    }

    /// Returns: the `nr` mutants that where last tested.
    MutationStatusTime[] getLatestMutants(const(Mutation.Kind)[] kinds, const long nr) @trusted {
        const sql = format("SELECT t0.id,t0.update_ts FROM %s t0, %s t1
                    WHERE
                    t0.update_ts IS NOT NULL AND
                    t1.st_id = t0.id AND
                    t1.kind IN (%(%s,%))
                    ORDER BY datetime(t0.update_ts) DESC LIMIT :limit",
                mutationStatusTable, mutationTable, kinds.map!(a => cast(int) a));
        auto stmt = db.prepare(sql);
        stmt.get.bind(":limit", nr);

        auto app = appender!(MutationStatusTime[])();
        foreach (res; stmt.get.execute)
            app.put(MutationStatusTime(MutationStatusId(res.peek!long(0)),
                    res.peek!string(1).fromSqLiteDateTime));
        return app.data;
    }

    /// Returns: the `nr` mutant with the highest count that has not been killed and existed in the system the longest.
    MutationStatus[] getHighestPrioMutant(const(Mutation.Kind)[] kinds,
            const Mutation.Status status, const long nr) @trusted {
        const sql = format("SELECT t0.id,t0.status,t0.prio,t0.update_ts,t0.added_ts
            FROM %s t0, %s t1
            WHERE
            t0.update_ts IS NOT NULL AND
            t0.status = :status AND
            t1.st_id = t0.id AND
            t1.kind IN (%(%s,%)) AND
            t1.st_id NOT IN (SELECT st_id FROM %s WHERE nomut != 0)
            ORDER BY t0.prio DESC LIMIT :limit", mutationStatusTable,
                mutationTable, kinds.map!(a => cast(int) a), srcMetadataTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":status", cast(long) status);
        stmt.get.bind(":limit", nr);

        auto app = appender!(MutationStatus[])();
        foreach (res; stmt.get.execute) {
            auto added = () {
                auto raw = res.peek!string(4);
                if (raw.length == 0)
                    return Nullable!SysTime();
                return Nullable!SysTime(raw.fromSqLiteDateTime);
            }();

            // dfmt off
            app.put(MutationStatus(
                MutationStatusId(res.peek!long(0)),
                res.peek!long(1).to!(Mutation.Status),
                res.peek!long(2).MutantPrio,
                res.peek!string(3).fromSqLiteDateTime,
                added,
            ));
            // dfmt on
        }

        return app.data;
    }

    /** Get SourceLoc for a specific mutation id.
     */
    Nullable!SourceLoc getSourceLocation(MutationId id) @trusted {
        auto s = format!"SELECT line, column FROM %s WHERE id IN (SELECT mp_id FROM %s WHERE id=:mut_id)"(
                mutationPointTable, mutationTable);
        auto stmt = db.prepare(s);
        stmt.get.bind(":mut_id", cast(long) id);
        typeof(return) rval;
        foreach (res; stmt.get.execute)
            rval = SourceLoc(res.peek!uint(0), res.peek!uint(1));
        return rval;
    }

    /** Remove all mutations of kinds.
     */
    void removeMutant(const Mutation.Kind[] kinds) @trusted {
        const s = format!"DELETE FROM %s WHERE id IN (SELECT mp_id FROM %s WHERE kind IN (%(%s,%)))"(
                mutationPointTable, mutationTable, kinds.map!(a => cast(int) a));
        auto stmt = db.prepare(s);
        stmt.get.execute;
    }

    /** Reset all mutations of kinds with the status `st` to unknown.
     */
    void resetMutant(const Mutation.Kind[] kinds, Mutation.Status st, Mutation.Status to_st) @trusted {
        const s = format!"UPDATE %s SET status=%s WHERE status = %s AND id IN(SELECT st_id FROM %s WHERE kind IN (%(%s,%)))"(
                mutationStatusTable, to_st.to!long, st.to!long,
                mutationTable, kinds.map!(a => cast(int) a));
        auto stmt = db.prepare(s);
        stmt.get.execute;
    }

    Mutation.Kind getKind(MutationId id) @trusted {
        static immutable sql = format!"SELECT kind FROM %s WHERE id=:id"(mutationTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", cast(long) id);

        typeof(return) rval;
        foreach (res; stmt.get.execute) {
            rval = res.peek!long(0).to!(Mutation.Kind);
        }
        return rval;
    }

    /// Returns: the `nr` mutants that where last tested.
    MutantTestTime[] getLatestMutantTimes(const(Mutation.Kind)[] kinds, const long nr) @trusted {
        const sql = format(
                "SELECT t0.id,t0.status,t0.compile_time_ms,t0.test_time_ms FROM %s t0, %s t1
                    WHERE
                    t0.update_ts IS NOT NULL AND
                    t1.st_id = t0.id AND
                    t1.kind IN (%(%s,%)) AND
                    (t0.compile_time_ms + t0.test_time_ms) > 0
                    ORDER BY datetime(t0.update_ts) DESC LIMIT :limit",
                mutationStatusTable, mutationTable, kinds.map!(a => cast(int) a));
        auto stmt = db.prepare(sql);
        stmt.get.bind(":limit", nr);

        auto app = appender!(MutantTestTime[])();
        foreach (res; stmt.get.execute)
            app.put(MutantTestTime(MutationStatusId(res.peek!long(0)),
                    res.peek!long(1).to!(Mutation.Status), res.peek!long(2)
                    .dur!"msecs", res.peek!long(3).dur!"msecs"));
        return app.data;
    }

    import dextool.plugin.mutate.backend.type;

    alias aliveSrcMutants = countMutants!([
        Mutation.Status.alive, Mutation.Status.noCoverage
    ]);
    alias killedSrcMutants = countMutants!([Mutation.Status.killed]);
    alias timeoutSrcMutants = countMutants!([Mutation.Status.timeout]);
    alias noCovSrcMutants = countMutants!([Mutation.Status.noCoverage]);
    alias equivalentMutants = countMutants!([Mutation.Status.equivalent]);
    alias skippedMutants = countMutants!([Mutation.Status.skipped]);
    alias memOverloadMutants = countMutants!([Mutation.Status.memOverload]);

    /// Returns: Total that should be counted when calculating the mutation score.
    alias totalSrcMutants = countMutants!([
        Mutation.Status.alive, Mutation.Status.killed, Mutation.Status.timeout,
        Mutation.Status.noCoverage, Mutation.Status.memOverload,
    ]);

    alias unknownSrcMutants = countMutants!([Mutation.Status.unknown]);
    alias killedByCompilerSrcMutants = countMutants!([
        Mutation.Status.killedByCompiler
    ]);

    /** Count the mutants with the nomut metadata.
     *
     * Params:
     *  status = status the mutants must be in to be counted.
     *  distinc = count based on unique source code changes.
     *  kinds = the kind of mutants to count.
     *  file = file to count mutants in.
     */
    private MutationReportEntry countMutants(int[] status)(const Mutation.Kind[] kinds,
            string file = null) @trusted {
        const qq = "
            SELECT count(*),sum(compile_time_ms),sum(test_time_ms)
            FROM (
            SELECT sum(t1.compile_time_ms) compile_time_ms,sum(t1.test_time_ms) test_time_ms
            FROM %s t0, %s t1%s
            WHERE
            %s
            t0.st_id = t1.id AND
            t1.status IN (%(%s,%)) AND
            t0.kind IN (%(%s,%))
            GROUP BY t1.id)";
        const query = () {
            auto fq = file.length == 0
                ? null : "t0.mp_id = t2.id AND t2.file_id = t3.id AND t3.path = :path AND";
            auto fq_from = file.length == 0 ? null : format(", %s t2, %s t3",
                    mutationPointTable, filesTable);
            return format(qq, mutationTable, mutationStatusTable, fq_from, fq,
                    status, kinds.map!(a => cast(int) a));
        }();

        typeof(return) rval;
        auto stmt = db.prepare(query);
        if (file.length != 0)
            stmt.get.bind(":path", file);
        auto res = stmt.get.execute;
        if (!res.empty) {
            rval = MutationReportEntry(res.front.peek!long(0),
                    MutantTimeProfile(res.front.peek!long(1).dur!"msecs",
                        res.front.peek!long(2).dur!"msecs"));
        }
        return rval;
    }

    /** Count the mutants with the nomut metadata.
     *
     * Params:
     *  status = status the mutants must be in to be counted.
     *  distinc = count based on unique source code changes.
     *  kinds = the kind of mutants to count.
     *  file = file to count mutants in.
     */
    private MetadataNoMutEntry countNoMutMutants(int[] status, bool distinct)(
            const Mutation.Kind[] kinds, string file = null) @trusted {
        static if (distinct) {
            auto sql_base = "
                SELECT count(*)
                FROM (
                SELECT count(*)
                FROM %s t0, %s t1,%s t4%s
                WHERE
                %s
                t0.st_id = t1.id AND
                t0.st_id = t4.st_id AND
                t4.nomut != 0 AND
                t1.status IN (%(%s,%)) AND
                t0.kind IN (%(%s,%))
                GROUP BY t1.id)";
        } else {
            auto sql_base = "
                SELECT count(*)
                FROM %s t0, %s t1,%s t4%s
                WHERE
                %s
                t0.st_id = t1.id AND
                t0.st_id = t4.st_id AND
                t4.nomut != 0 AND
                t1.status IN (%(%s,%)) AND
                t0.kind IN (%(%s,%))";
        }
        const query = () {
            auto fq = file.length == 0
                ? null : "t0.mp_id = t2.id AND t2.file_id = t3.id AND t3.path = :path AND";
            auto fq_from = file.length == 0 ? null : format(", %s t2, %s t3",
                    mutationPointTable, filesTable);
            return format(sql_base, mutationTable, mutationStatusTable,
                    srcMetadataTable, fq_from, fq, status, kinds.map!(a => cast(int) a));
        }();

        typeof(return) rval;
        auto stmt = db.prepare(query);
        if (file.length != 0)
            stmt.get.bind(":path", file);
        auto res = stmt.get.execute;
        if (!res.empty)
            rval = MetadataNoMutEntry(res.front.peek!long(0));
        return rval;
    }

    /// ditto.
    alias aliveNoMutSrcMutants = countNoMutMutants!([
        Mutation.Status.alive, Mutation.Status.noCoverage
    ], true);

    Nullable!Checksum getChecksum(MutationStatusId id) @trusted {
        static immutable sql = format!"SELECT checksum0, checksum1 FROM %s WHERE id=:id"(
                mutationStatusTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", id.get);

        typeof(return) rval;
        foreach (res; stmt.get.execute) {
            rval = Checksum(res.peek!long(0), res.peek!long(1));
            break;
        }
        return rval;
    }

    /// Store all found mutants.
    void put(MutationPointEntry2[] mps, AbsolutePath root) @trusted {
        if (mps.empty)
            return;

        static immutable insert_mp_sql = "INSERT OR IGNORE INTO " ~ mutationPointTable ~ "
            (file_id, offset_begin, offset_end, line, column, line_end, column_end)
            SELECT id,:begin,:end,:line,:column,:line_end,:column_end
            FROM " ~ filesTable ~ " WHERE path = :path";
        auto mp_stmt = db.prepare(insert_mp_sql);

        foreach (mp; mps) {
            auto rel_file = relativePath(mp.file, root).Path;
            mp_stmt.get.bind(":begin", mp.offset.begin);
            mp_stmt.get.bind(":end", mp.offset.end);
            mp_stmt.get.bind(":line", mp.sloc.line);
            mp_stmt.get.bind(":column", mp.sloc.column);
            mp_stmt.get.bind(":line_end", mp.slocEnd.line);
            mp_stmt.get.bind(":column_end", mp.slocEnd.column);
            mp_stmt.get.bind(":path", cast(string) rel_file);
            mp_stmt.get.execute;
            mp_stmt.get.reset;
        }

        static immutable insert_cmut_sql = "INSERT OR IGNORE INTO " ~ mutationStatusTable
            ~ " (status,exit_code,compile_time_ms,test_time_ms,update_ts,added_ts,checksum0,checksum1,prio)
            VALUES(:st,0,0,0,:update_ts,:added_ts,:c0,:c1,:prio)";
        auto cmut_stmt = db.prepare(insert_cmut_sql);
        const ts = Clock.currTime.toSqliteDateTime;
        cmut_stmt.get.bind(":st", Mutation.Status.unknown);
        cmut_stmt.get.bind(":update_ts", ts);
        cmut_stmt.get.bind(":added_ts", ts);
        foreach (mp; mps) {
            const prio = (mp.offset.begin < mp.offset.end) ? mp.offset.end - mp.offset.begin : 0;
            cmut_stmt.get.bind(":c0", cast(long) mp.cm.id.c0);
            cmut_stmt.get.bind(":c1", cast(long) mp.cm.id.c1);
            cmut_stmt.get.bind(":prio", prio);
            cmut_stmt.get.execute;
            cmut_stmt.get.reset;
        }

        static immutable insert_m_sql = "INSERT OR IGNORE INTO "
            ~ mutationTable ~ " (mp_id, st_id, kind)
            SELECT t0.id,t1.id,:kind FROM " ~ mutationPointTable ~ " t0, "
            ~ mutationStatusTable ~ " t1, " ~ filesTable ~ " t2 WHERE
            t2.path = :path AND
            t0.file_id = t2.id AND
            t0.offset_begin = :off_begin AND
            t0.offset_end = :off_end AND
            t1.checksum0 = :c0 AND
            t1.checksum1 = :c1";
        auto insert_m = db.prepare(insert_m_sql);

        foreach (mp; mps) {
            auto rel_file = relativePath(mp.file, root).Path;
            insert_m.get.bind(":path", cast(string) rel_file);
            insert_m.get.bind(":off_begin", mp.offset.begin);
            insert_m.get.bind(":off_end", mp.offset.end);
            insert_m.get.bind(":c0", cast(long) mp.cm.id.c0);
            insert_m.get.bind(":c1", cast(long) mp.cm.id.c1);
            insert_m.get.bind(":kind", mp.cm.mut.kind);
            insert_m.get.execute;
            insert_m.get.reset;
        }
    }

    /// Remove mutants that have no connection to a mutation point, orphaned mutants.
    void removeOrphanedMutants(void delegate(size_t i, size_t total, const Duration avgRemoveTime,
            const Duration timeLeft, SysTime predDoneAt) progress, void delegate(size_t total) done) @trusted {
        import std.datetime.stopwatch : StopWatch, AutoStart;

        const removeIds = () {
            static immutable sql = "SELECT id FROM " ~ mutationStatusTable
                ~ " WHERE id NOT IN (SELECT st_id FROM " ~ mutationTable ~ ")";
            auto stmt = db.prepare(sql);
            auto removeIds = appender!(long[])();
            foreach (res; stmt.get.execute)
                removeIds.put(res.peek!long(0));
            return removeIds.data;
        }();

        immutable batchNr = 1000;
        static immutable sql = "DELETE FROM " ~ mutationStatusTable ~ " WHERE id=:id";
        auto stmt = db.prepare(sql);
        auto sw = StopWatch(AutoStart.yes);
        foreach (const i, const id; removeIds) {
            stmt.get.bind(":id", id);
            stmt.get.execute;
            stmt.get.reset;

            // continuously print to inform the user of the progress and avoid
            // e.g. timeout on jenkins.
            if (i > 0 && i % batchNr == 0) {
                const avg = cast(long)(cast(double) sw.peek.total!"msecs" / cast(double) batchNr);
                const t = dur!"msecs"(avg * (removeIds.length - i));
                progress(i, removeIds.length, avg.dur!"msecs", t, Clock.currTime + t);
                sw.reset;
            }
        }

        done(removeIds.length);
    }

    /// Returns: all alive mutants on the same mutation point as `id`.
    MutationStatusId[] getSurroundingAliveMutants(const MutationStatusId id) @trusted {
        long mp_id;
        {
            auto stmt = db.prepare(
                    "SELECT DISTINCT mp_id FROM " ~ mutationTable ~ " WHERE st_id=:id");
            stmt.get.bind(":id", id.get);
            auto res = stmt.get.execute;
            if (res.empty)
                return null;
            mp_id = res.oneValue!long;
        }

        static immutable sql = format!"SELECT DISTINCT t0.st_id FROM %s t0, %s t1 WHERE
            t0.mp_id = :id AND
            t0.st_id = t1.id AND
            t1.status = %s"(mutationTable, mutationStatusTable, cast(int) Mutation.Status.alive);

        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", mp_id);

        auto rval = appender!(MutationStatusId[])();
        foreach (a; stmt.get.execute)
            rval.put(a.peek!long(0).MutationStatusId);
        return rval.data;
    }

    MutationStatusId[] mutantsInRegion(const FileId id, const Offset region,
            const Mutation.Status status, const Mutation.Kind[] kinds) @trusted {
        const sql = format!"SELECT DISTINCT t1.st_id
            FROM %s t0, %s t1, %s t2
            WHERE t0.file_id = :file_id AND
            t0.id = t1.mp_id AND
            (t0.offset_begin BETWEEN :begin AND :end) AND
            (t0.offset_end BETWEEN :begin AND :end) AND
            t1.st_id = t2.id AND
            t2.status = :status AND
            t1.kind IN (%(%s,%))
            "(mutationPointTable, mutationTable, mutationStatusTable, kinds.map!(a => cast(int) a));

        auto stmt = db.prepare(sql);
        stmt.get.bind(":file_id", id.get);
        stmt.get.bind(":begin", region.begin);
        stmt.get.bind(":end", region.end);
        stmt.get.bind(":status", cast(int) status);
        auto app = appender!(MutationStatusId[])();
        foreach (ref r; stmt.get.execute)
            app.put(MutationStatusId(r.peek!long(0)));
        return app.data;
    }
}

struct DbWorklist {
    private Miniorm* db_;

    scope ref Miniorm db() return @safe {
        return *db_;
    }

    /** Add all mutants with the specific status to the worklist.
     */
    void update(const Mutation.Kind[] kinds, const Mutation.Status[] status,
            const long basePrio = 100, const MutationOrder userOrder = MutationOrder.random) @trusted {
        const order = fromOrder(userOrder);

        const sql = format!"INSERT OR IGNORE INTO %s (id,prio)
            SELECT t1.id,%s FROM %s t0, %s t1 WHERE t0.kind IN (%(%s,%)) AND
            t0.st_id = t1.id AND
            t1.status IN (%(%s,%))
            "(mutantWorklistTable, order, mutationTable, mutationStatusTable,
                kinds.map!(a => cast(int) a), status.map!(a => cast(int) a));
        auto stmt = db.prepare(sql);
        stmt.get.bind(":base_prio", basePrio);
        stmt.get.execute;
    }

    /// Add a mutant to the worklist.
    void add(const MutationStatusId id, const long basePrio = 0,
            const MutationOrder userOrder = MutationOrder.consecutive) @trusted {
        const order = fromOrder(userOrder);
        const sql = format!"INSERT OR REPLACE INTO %s (id,prio)
            SELECT t1.id,%s FROM %s t1 WHERE t1.id = :id
            "(mutantWorklistTable, order, mutationStatusTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", id.get);
        stmt.get.bind(":base_prio", basePrio);
        stmt.get.execute;
    }

    /// Remove a mutant from the worklist.
    void remove(const MutationStatusId id) @trusted {
        static immutable sql = "DELETE FROM " ~ mutantWorklistTable ~ " WHERE id = :id";
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", id.get);
        stmt.get.execute;
    }

    /// Remove all mutants with `status` from the worklist.
    void remove(const Mutation.Status status) @trusted {
        static immutable sql = "DELETE FROM " ~ mutantWorklistTable ~ " WHERE "
            ~ " id IN (SELECT id FROM " ~ mutationStatusTable ~ " WHERE status=:status)";
        auto stmt = db.prepare(sql);
        stmt.get.bind(":status", cast(ubyte) status);
        stmt.get.execute;
    }

    void clear() @trusted {
        static immutable sql = format!"DELETE FROM " ~ mutantWorklistTable;
        auto stmt = db.prepare(sql);
        stmt.get.execute;
    }

    long getCount() @trusted {
        static immutable sql = "SELECT count(*) FROM " ~ mutantWorklistTable;
        auto stmt = db.prepare(sql);
        auto res = stmt.get.execute;
        return res.oneValue!long;
    }

    long getCount(Mutation.Status[] status) @trusted {
        const sql = format("SELECT count(*) FROM " ~ mutantWorklistTable ~ " t0, "
                ~ mutationStatusTable ~ " t1 WHERE t0.id=t1.id AND t1.status IN (%(%s,%))",
                status.map!(a => cast(int) a));
        auto stmt = db.prepare(sql);
        auto res = stmt.get.execute;
        return res.oneValue!long;
    }

    /// All mutants in the worklist ordred by their priority
    WorklistItem[] getAll() @trusted {
        static immutable sql = "SELECT id,prio FROM " ~ mutantWorklistTable ~ " ORDER BY prio DESC";
        auto stmt = db.prepare(sql);
        auto res = stmt.get.execute;
        return res.map!(a => WorklistItem(a.peek!long(0).MutationStatusId,
                a.peek!long(1).MutantPrio)).array;
    }

    /// Add all mutants with `status` to worklist
    void statusToWorklist(const Mutation.Status status, const long prio = 100) @trusted {
        immutable sql = format!"INSERT OR IGNORE INTO %1$s (id,prio)
            SELECT id,%3$s+prio FROM %2$s WHERE status=:status"(mutantWorklistTable,
                mutationStatusTable, prio);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":status", cast(int) status);
        stmt.get.execute;
    }
}

struct DbMemOverload {
    private Miniorm* db_;

    scope ref Miniorm db() return @safe {
        return *db_;
    }

    void put(const MutationStatusId id) @trusted {
        immutable sql = "INSERT OR IGNORE INTO "
            ~ mutantMemOverloadWorklistTable ~ " (id) VALUES (:id)";
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", id.get);
        stmt.get.execute;
    }

    /// Copy the memory overload mutants to the worklist of mutants to test.
    void toWorklist(const long prio = 100) @trusted {
        immutable sql = format!"INSERT OR IGNORE INTO %1$s (id,prio)
            SELECT id,%3$s FROM %2$s"(mutantWorklistTable, mutantMemOverloadWorklistTable, prio);
        auto stmt = db.prepare(sql);
        stmt.get.execute;

    }

    void clear() @trusted {
        immutable sql = "DELETE FROM " ~ mutantMemOverloadWorklistTable;
        db.run(sql);
    }
}

struct DbMarkMutant {
    private Miniorm* db_;

    scope ref Miniorm db() return @safe {
        return *db_;
    }

    bool isMarked(MutationId id) @trusted {
        static immutable s = format!"SELECT COUNT(*) FROM %s WHERE st_id IN
            (SELECT st_id FROM %s WHERE id=:id)"(markedMutantTable, mutationTable);
        auto stmt = db.prepare(s);
        stmt.get.bind(":id", cast(long) id);
        auto res = stmt.get.execute;
        return res.oneValue!long != 0;
    }

    /// All marked mutants whom have a mutation status checksum that has been removed from the database.
    MarkedMutant[] getLostMarkings() @trusted {
        static immutable sql = format!"SELECT checksum0 FROM %s
            WHERE
            checksum0 NOT IN (SELECT checksum0 FROM %s)"(markedMutantTable, mutationStatusTable);

        auto stmt = db.prepare(sql);
        auto app = appender!(MarkedMutant[])();
        foreach (res; stmt.get.execute) {
            foreach (m; db.run(select!MarkedMutantTbl.where("checksum0 = :cs0",
                    Bind("cs0")), res.peek!long(0))) {
                app.put(.make(m));
            }
        }

        return app.data;
    }

    /** Mark a mutant with status and rationale (also adds metadata).
     */
    void mark(const MutationId id, const Path file, const SourceLoc sloc, const MutationStatusId statusId,
            const Checksum cs, const Mutation.Status s, const Rationale r, string mutationTxt) @trusted {
        db.run(insertOrReplace!MarkedMutantTbl, MarkedMutantTbl(cs.c0, cs.c1,
                statusId.get, id.get, sloc.line, sloc.column, file, s,
                Clock.currTime.toUTC, r.get, mutationTxt));
    }

    void remove(const Checksum cs) @trusted {
        db.run(delete_!MarkedMutantTbl.where("checksum0 = :cs0", Bind("cs0")), cast(long) cs.c0);
    }

    void remove(const MutationStatusId id) @trusted {
        db.run(delete_!MarkedMutantTbl.where("st_id = :st_id", Bind("st_id")), id.get);
    }

    /// Returns: All mutants with that are marked orderd by their path
    MarkedMutant[] getMarkedMutants() @trusted {
        import miniorm : OrderingTermSort;

        auto app = appender!(MarkedMutant[])();
        foreach (m; db.run(select!MarkedMutantTbl.orderBy(OrderingTermSort.ASC, [
                    "path"
                ]))) {
            app.put(.make(m));
        }

        return app.data;
    }
}

struct DbTimeout {
    private Miniorm* db_;

    scope ref Miniorm db() return @safe {
        return *db_;
    }

    /// Returns: the context for the timeout algorithm.
    MutantTimeoutCtx getMutantTimeoutCtx() @trusted {
        foreach (res; db.run(select!MutantTimeoutCtx))
            return res;
        return MutantTimeoutCtx.init;
    }

    void put(const MutantTimeoutCtx ctx) @trusted {
        db.run(delete_!MutantTimeoutCtx);
        db.run(insert!MutantTimeoutCtx.insert, ctx);
    }

    void put(const MutationStatusId id, const long iter) @trusted {
        static immutable sql = "INSERT OR REPLACE INTO "
            ~ mutantTimeoutWorklistTable ~ " (id,iter) VALUES (:id,:iter)";
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", id.get);
        stmt.get.bind(":iter", iter);
        stmt.get.execute;
    }

    void update(const MutationStatusId id, const long iter) @trusted {
        static immutable sql = "UPDATE " ~ mutantTimeoutWorklistTable
            ~ " SET iter=:iter WHERE id=:id";
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", id.get);
        stmt.get.bind(":iter", iter);
        stmt.get.execute;
    }

    /** Remove all mutants that are in the worklist of the iteration run `iter`
     * that do NOT have the mutation status timeout.
     */
    void reduceMutantTimeoutWorklist(const long iter) @trusted {
        static immutable sql = "DELETE FROM " ~ mutantTimeoutWorklistTable ~ " WHERE id IN (SELECT id FROM "
            ~ mutationStatusTable ~ " WHERE status != :status)" ~ " AND iter=:iter";
        auto stmt = db.prepare(sql);
        stmt.get.bind(":status", cast(ubyte) Mutation.Status.timeout);
        stmt.get.bind(":iter", iter);
        stmt.get.execute;
    }

    /// Remove all mutants from the worklist.
    void clearMutantTimeoutWorklist() @trusted {
        static immutable sql = "DELETE FROM " ~ mutantTimeoutWorklistTable;
        db.run(sql);
    }

    /// Returns: the number of mutants in the worklist.
    long countMutantTimeoutWorklist() @trusted {
        static immutable sql = "SELECT count(*) FROM " ~ mutantTimeoutWorklistTable;
        auto stmt = db.prepare(sql);
        auto res = stmt.get.execute();
        return res.oneValue!long;
    }

    /// Changes the status of mutants in the timeout worklist to unknown.
    void resetMutantTimeoutWorklist(Mutation.Status toStatus) @trusted {
        static immutable sql = format!"UPDATE %1$s SET status=:st WHERE id IN (SELECT id FROM %2$s)"(
                mutationStatusTable, mutantTimeoutWorklistTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":st", cast(ubyte) toStatus);
        stmt.get.execute;
    }

    /// Copy the timeout mutants to the worklist of mutants to test.
    void copyMutantTimeoutWorklist(const long iter, const long prio = 100) @trusted {
        immutable sql = format!"INSERT OR IGNORE INTO %1$s (id,prio)
            SELECT id,%3$s FROM %2$s WHERE iter=:iter"(mutantWorklistTable,
                mutantTimeoutWorklistTable, prio);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":iter", iter);
        stmt.get.execute;
    }
}

struct DbCoverage {
    private Miniorm* db_;

    scope ref Miniorm db() return @safe {
        return *db_;
    }

    /// Add coverage regions.
    void putCoverageMap(const FileId id, const Offset[] region) @trusted {
        static immutable sql = format!"INSERT OR IGNORE INTO %1$s (file_id, begin, end)
            VALUES(:fid, :begin, :end)"(srcCovTable);
        auto stmt = db.prepare(sql);

        foreach (a; region) {
            stmt.get.bind(":fid", id.get);
            stmt.get.bind(":begin", a.begin);
            stmt.get.bind(":end", a.end);
            stmt.get.execute;
            stmt.get.reset;
        }
    }

    CovRegion[][FileId] getCoverageMap() @trusted {
        static immutable sql = format!"SELECT file_id,begin,end,id FROM %s"(srcCovTable);
        auto stmt = db.prepare(sql);

        typeof(return) rval;
        foreach (ref r; stmt.get.execute) {
            auto region = CovRegion(r.peek!long(3).CoverageRegionId,
                    Offset(r.peek!uint(1), r.peek!uint(2)));
            if (auto v = FileId(r.peek!long(0)) in rval) {
                *v ~= region;
            } else {
                rval[FileId(r.peek!long(0))] = [region];
            }
        }

        return rval;
    }

    long getCoverageMapCount() @trusted {
        static immutable sql = format!"SELECT count(*) FROM %s"(srcCovTable);
        auto stmt = db.prepare(sql);
        foreach (ref r; stmt.get.execute)
            return r.peek!long(0);
        return 0;
    }

    void clearCoverageMap(const FileId id) @trusted {
        static immutable sql = "DELETE FROM " ~ srcCovTable ~ " WHERE file_id = :id";
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", id.get);
        stmt.get.execute;
    }

    void putCoverageInfo(const CoverageRegionId regionId, bool status) {
        static immutable sql = format!"INSERT OR REPLACE INTO %1$s (id, status) VALUES(:id, :status)"(
                srcCovInfoTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", regionId.get);
        stmt.get.bind(":status", status);
        stmt.get.execute;
    }

    Optional!SysTime getCoverageTimeStamp() @trusted {
        static immutable sql = format!"SELECT timeStamp FROM %s"(srcCovTimeStampTable);
        auto stmt = db.prepare(sql);

        foreach (ref r; stmt.get.execute) {
            return some(r.peek!string(0).fromSqLiteDateTime);
        }
        return none!SysTime;
    }

    /// Set the timestamp to the current UTC time.
    void updateCoverageTimeStamp() @trusted {
        static immutable sql = format!"INSERT OR REPLACE INTO %s (id, timestamp) VALUES(0, :time)"(
                srcCovTimeStampTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":time", Clock.currTime.toSqliteDateTime);
        stmt.get.execute;
    }

    MutationStatusId[] getNotCoveredMutants() @trusted {
        static immutable sql = format!"SELECT DISTINCT t3.st_id FROM %1$s t0, %2$s t1, %3$s t2, %4$s t3
            WHERE t0.status = 0 AND
            t0.id = t1.id AND
            t1.file_id = t2.file_id AND
            (t2.offset_begin BETWEEN t1.begin AND t1.end) AND
            (t2.offset_end BETWEEN t1.begin AND t1.end) AND
            t2.id = t3.mp_id"(srcCovInfoTable, srcCovTable, mutationPointTable, mutationTable);

        auto app = appender!(MutationStatusId[])();
        auto stmt = db.prepare(sql);
        foreach (ref r; stmt.get.execute) {
            app.put(MutationStatusId(r.peek!long(0)));
        }

        return app.data;
    }
}

struct DbSchema {
    import my.hash : Checksum64;

    private Miniorm* db_;
    private Database* wrapperDb;

    scope ref Miniorm db() return @safe {
        return *db_;
    }

    /// Returns: all schematas excluding those that are known to not be
    /// possible to compile.
    SchemataId[] getSchematas(const SchemaStatus exclude) @trusted {
        static immutable sql = format!"SELECT t0.id
            FROM %1$s t0
            WHERE
            t0.id NOT IN (SELECT id FROM %2$s WHERE status = :status)"(schemataTable,
                schemataUsedTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":status", cast(long) exclude);
        auto app = appender!(SchemataId[])();
        foreach (a; stmt.get.execute) {
            app.put(SchemataId(a.peek!long(0)));
        }
        return app.data;
    }

    Nullable!Schemata getSchemata(SchemataId id) @trusted {
        import std.zlib : uncompress;

        static immutable sql = format!"SELECT
            t1.path, t0.text, t0.offset_begin, t0.offset_end
            FROM %1$s t0, %2$s t1
            WHERE
            t0.schem_id = :id AND
            t0.file_id = t1.id
            ORDER BY t0.order_ ASC
            "(schemataFragmentTable, filesTable);

        typeof(return) rval;
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", cast(long) id);

        auto app = appender!(SchemataFragment[])();
        foreach (a; stmt.get.execute) {
            auto raw = a.peek!(ubyte[])(1);
            auto offset = Offset(a.peek!uint(2), a.peek!uint(3));
            app.put(SchemataFragment(a.peek!string(0).Path, offset,
                    cast(const(ubyte)[]) uncompress(raw, offset.end - offset.begin)));
        }

        if (!app.data.empty) {
            rval = Schemata(SchemataId(id), app.data);
        }

        return rval;
    }

    /// Returns: number of mutants in a schema with `status`.
    long countMutants(const SchemataId id, const Mutation.Kind[] kinds,
            const Mutation.Status[] status) @trusted {
        const sql = format!"SELECT count(*)
        FROM %s t1, %s t2, %s t3
        WHERE
        t1.schem_id = :id AND
        t1.st_id = t2.id AND
        t3.st_id = t1.st_id AND
        t3.kind IN (%(%s,%)) AND
        t2.status IN (%(%s,%))
        "(schemataMutantTable, mutationStatusTable, mutationTable,
                kinds.map!(a => cast(int) a), status.map!(a => cast(int) a));

        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", id.get);
        return stmt.get.execute.oneValue!long;
    }

    /// Returns: number of mutants in a schema that are marked for testing and in the worklist.
    long countMutantsInWorklist(const SchemataId id, const Mutation.Kind[] kinds) @trusted {
        const sql = format!"SELECT count(*)
        FROM %s t1, %s t2, %s t3, %s t4
        WHERE
        t1.schem_id = :id AND
        t1.st_id = t2.id AND
        t3.st_id = t1.st_id AND
        t2.id = t4.id AND
        t3.kind IN (%(%s,%))
        "(schemataMutantTable, mutationStatusTable, mutationTable,
                mutantWorklistTable, kinds.map!(a => cast(int) a));

        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", id.get);
        return stmt.get.execute.oneValue!long;
    }

    MutationStatusId[] getSchemataMutants(const SchemataId id, const Mutation.Kind[] kinds) @trusted {
        // TODO: DISTINCT should not be needed. Instead use e.g. a constraint on the table or something
        immutable sql = format!"SELECT DISTINCT t1.st_id
            FROM %s t1, %s t2, %s t3, %s t4
            WHERE
            t1.schem_id = :id AND
            t1.st_id = t2.id AND
            t3.st_id = t1.st_id AND
            t2.id = t4.id AND
            t3.kind IN (%(%s,%))
            "(schemataMutantTable, mutationStatusTable, mutationTable,
                mutantWorklistTable, kinds.map!(a => cast(int) a));
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", id.get);

        auto app = appender!(MutationStatusId[])();
        foreach (a; stmt.get.execute) {
            app.put(a.peek!long(0).MutationStatusId);
        }

        return app.data;
    }

    /// Returns: the kind of mutants a schemata contains.
    Mutation.Kind[] getSchemataKinds(const SchemataId id) @trusted {
        static immutable sql = format!"SELECT DISTINCT t1.kind
            FROM %1$s t0, %2$s t1
            WHERE
            t0.schem_id = :id AND
            t0.st_id = t1.st_id
            "(schemataMutantTable, mutationTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", cast(long) id);

        auto app = appender!(Mutation.Kind[])();
        foreach (a; stmt.get.execute) {
            app.put(a.peek!long(0).to!(Mutation.Kind));
        }

        return app.data;
    }

    /// Mark a schemata as used.
    void markUsed(const SchemataId id, const SchemaStatus status) @trusted {
        static immutable sql = format!"INSERT OR IGNORE INTO %1$s VALUES(:id, :status)"(
                schemataUsedTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", cast(long) id);
        stmt.get.bind(":status", status);
        stmt.get.execute;
    }

    /// Create a schemata from a bundle of fragments.
    Nullable!SchemataId putSchemata(SchemataChecksum cs,
            const SchemataFragment[] fragments, MutationStatusId[] mutants) @trusted {
        import std.zlib : compress;

        const schemId = cast(long) cs.value.c0;

        const exists = () {
            static immutable sql = format!"SELECT count(*) FROM %1$s WHERE id=:id"(schemataTable);
            auto stmt = db.prepare(sql);
            stmt.get.bind(":id", schemId);
            return stmt.get.execute.oneValue!long != 0;

        }();

        if (exists)
            return typeof(return)();

        {
            static immutable sql = format!"INSERT INTO %1$s VALUES(:id, :nr)"(schemataTable);
            auto stmt = db.prepare(sql);
            stmt.get.bind(":id", cast(long) cs.value.c0);
            stmt.get.bind(":nr", cast(long) fragments.length);
            stmt.get.execute;
        }

        foreach (f; fragments.enumerate) {
            const fileId = wrapperDb.getFileId(f.value.file);
            if (fileId.isNull) {
                logger.warningf("Unable to add schemata fragment for file %s because it doesn't exist",
                        f.value.file);
                continue;
            }

            db.run(insert!SchemataFragmentTable, SchemataFragmentTable(0,
                    schemId, cast(long) fileId.get, f.index,
                    compress(f.value.text), f.value.offset.begin, f.value.offset.end));
        }

        // relate mutants to this schemata.
        db.run(insertOrIgnore!SchemataMutantTable,
                mutants.map!(a => SchemataMutantTable(cast(long) a, schemId)));

        return typeof(return)(schemId.SchemataId);
    }

    /// Prunes the database of schemas that where created by an older version.
    void deleteAllSchemas() @trusted {
        db.run(delete_!SchemataTable);
    }

    /// Prunes the database of schemas that are unusable.
    void pruneSchemas() @trusted {
        auto remove = () {
            auto remove = appender!(long[])();

            // remove those that have lost some fragments
            static immutable sqlFragment = format!"SELECT t0.id
            FROM
            %1$s t0,
            (SELECT schem_id id,count(*) fragments FROM %2$s GROUP BY schem_id) t1
            WHERE
            t0.id = t1.id AND
            t0.fragments != t1.fragments
            "(schemataTable, schemataFragmentTable);
            auto stmt = db.prepare(sqlFragment);
            foreach (a; stmt.get.execute) {
                remove.put(a.peek!long(0));
            }

            // remove those that have lost all fragments
            static immutable sqlNoFragment = format!"SELECT t0.id FROM %1$s t0 WHERE t0.id NOT IN (SELECT schem_id FROM %2$s)"(
                    schemataTable, schemataFragmentTable);
            stmt = db.prepare(sqlNoFragment);
            foreach (a; stmt.get.execute) {
                remove.put(a.peek!long(0));
            }

            return remove.data;
        }();

        static immutable sql = "DELETE FROM " ~ schemataTable ~ " WHERE id=:id";
        auto stmt = db.prepare(sql);
        foreach (a; remove) {
            stmt.get.bind(":id", a);
            stmt.get.execute;
            stmt.get.reset;
        }
    }

    /** Removes all schemas that either do not compile or have zero mutants.
     *
     * Returns: number of schemas removed.
     */
    long pruneUsedSchemas(const SchemaStatus[] status) @trusted {
        auto remove = () {
            auto remove = appender!(long[])();

            auto sqlUsed = format!"SELECT id FROM %s WHERE status IN (%(%s,%))"(schemataUsedTable,
                    status.map!(a => cast(long) a));
            auto stmt = db.prepare(sqlUsed);
            foreach (a; stmt.get.execute) {
                remove.put(a.peek!long(0));
            }
            return remove.data;
        }();

        static immutable sql = "DELETE FROM " ~ schemataTable ~ " WHERE id=:id";
        auto stmt = db.prepare(sql);
        foreach (a; remove) {
            stmt.get.bind(":id", a);
            stmt.get.execute;
            stmt.get.reset;
        }

        return remove.length;
    }

    int[Mutation.Kind][Checksum64] getMutantProbability() @trusted {
        typeof(return) rval;

        auto stmt = db.prepare(
                format!"SELECT kind,probability,path FROM %1$s"(schemaMutantQTable));
        foreach (ref r; stmt.get.execute) {
            const ch = Checksum64(cast(ulong) r.peek!long(2));
            rval.require(ch, (int[Mutation.Kind]).init);
            rval[ch][r.peek!long(0).to!(Mutation.Kind)] = r.peek!int(1);
        }
        return rval;
    }

    void removeMutantProbability(const Checksum64 p) @trusted {
        static immutable sql = "DELETE FROM " ~ schemaMutantQTable ~ " WHERE path=:path";
        auto stmt = db.prepare(sql);
        stmt.get.bind(":path", cast(long) p.c0);
        stmt.get.execute;
    }

    /** Save the probability state for a path.
     *
     * Only states other than 100 are saved.
     *
     * Params:
     *  p = checksum of the path.
     */
    void saveMutantProbability(const Checksum64 p, int[Mutation.Kind] state, const int skipMax) @trusted {
        auto stmt = db.prepare(
                format!"INSERT OR REPLACE INTO %1$s (kind,probability,path) VALUES(:kind,:q,:path)"(
                schemaMutantQTable));
        foreach (a; state.byKeyValue) {
            if (a.value != skipMax) {
                stmt.get.bind(":kind", cast(long) a.key);
                stmt.get.bind(":q", cast(long) a.value);
                stmt.get.bind(":path", cast(long) p.c0);
                stmt.get.execute;
                stmt.get.reset;
            }
        }
    }

    /// Returns: all mutant subtypes that has `status`, can occur multiple times.
    Mutation.Kind[] getSchemaUsedKinds(const Path p, const SchemaStatus status) @trusted {
        static immutable sql = format!"SELECT DISTINCT t1.kind
            FROM %1$s t0, %2$s t1, %3$s t2, %4$s t3, %5$s t4
            WHERE
            t4.status = :status AND
            t4.id = t0.schem_id AND
            t0.st_id = t1.st_id AND
            t1.mp_id = t2.id AND
            t2.file_id = t3.id AND
            t3.path = :path
            "(schemataMutantTable, mutationTable, mutationPointTable,
                filesTable, schemataUsedTable);

        auto stmt = db.prepare(sql);
        stmt.get.bind(":status", cast(long) status);
        stmt.get.bind(":path", p.toString);

        auto app = appender!(Mutation.Kind[])();
        foreach (ref r; stmt.get.execute) {
            auto k = r.peek!long(0).to!(Mutation.Kind);
            app.put(k);
        }

        return app.data;
    }

    /// Returns: an array of the mutants that are in schemas with the specific status
    long[] schemaMutantCount(const SchemaStatus status) @trusted {
        static immutable sql = format!"SELECT (SELECT count(*) FROM %2$s WHERE schem_id=t0.id)
            FROM %1$s t0 WHERE status=:status"(schemataUsedTable, schemataMutantTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":status", cast(long) status);
        auto app = appender!(long[])();
        foreach (ref r; stmt.get.execute)
            app.put(r.peek!long(0));
        return app.data;
    }

    long getSchemaSize(const long defaultValue) @trusted {
        static immutable sql = "SELECT size FROM " ~ schemaSizeQTable ~ " WHERE id=0";
        auto stmt = db.prepare(sql);
        foreach (ref r; stmt.get.execute)
            return r.peek!long(0);
        return defaultValue;
    }

    void saveSchemaSize(const long v) @trusted {
        static immutable sql = "INSERT OR REPLACE INTO " ~ schemaSizeQTable
            ~ " (id,size) VALUES(0,:size)";
        auto stmt = db.prepare(sql);
        stmt.get.bind(":size", v);
        stmt.get.execute;
    }
}

struct DbMetaData {
    private Miniorm* db_;

    scope ref Miniorm db() return @safe {
        return *db_;
    }

    LineMetadata getLineMetadata(const FileId fid, const SourceLoc sloc) @trusted {
        // TODO: change this select to using microrm
        static immutable sql = format("SELECT nomut,tag,comment FROM %s
            WHERE
            file_id = :fid AND
            line = :line", rawSrcMetadataTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":fid", cast(long) fid);
        stmt.get.bind(":line", sloc.line);

        auto rval = typeof(return)(fid, sloc.line);
        foreach (res; stmt.get.execute) {
            if (res.peek!long(0) != 0)
                rval.set(NoMut(res.peek!string(1), res.peek!string(2)));
        }

        return rval;
    }

    /// Remove all metadata.
    void clearMetadata() {
        static immutable sql = "DELETE FROM " ~ rawSrcMetadataTable;
        db.run(sql);
    }

    /** Save line metadata to the database which is used to associate line
     * metadata with mutants.
     */
    void put(const LineMetadata[] mdata) {
        import sumtype;

        if (mdata.empty)
            return;

        // TODO: convert to microrm
        static immutable sql = "INSERT OR IGNORE INTO " ~ rawSrcMetadataTable ~ "
            (file_id, line, nomut, tag, comment)
            VALUES(:fid, :line, :nomut, :tag, :comment)";

        auto stmt = db.prepare(sql);
        foreach (meta; mdata) {
            auto nomut = meta.attr.match!((NoMetadata a) => NoMut.init, (NoMut a) => a);
            stmt.get.bindAll(cast(long) meta.id, meta.line, meta.isNoMut,
                    nomut.tag, nomut.comment);
            stmt.get.execute;
            stmt.get.reset;
        }
    }

    /** Update the content of metadata tables with what has been added to the
     * raw table data.
     */
    void updateMetadata() @trusted {
        db.run("DELETE FROM " ~ srcMetadataTable);
        db.run("DELETE FROM " ~ nomutTable);
        db.run("DELETE FROM " ~ nomutDataTable);

        static immutable nomut_tbl = "INSERT INTO %s
            SELECT
                t0.id mp_id,
                t1.line line,
                count(*) status
                FROM %s t0, %s t1
                WHERE
                t0.file_id = t1.file_id AND
                (t1.line BETWEEN t0.line AND t0.line_end)
                GROUP BY
                t0.id";
        db.run(format!nomut_tbl(nomutTable, mutationPointTable, rawSrcMetadataTable));

        static immutable src_metadata_sql = "INSERT INTO %s
            SELECT DISTINCT
            t0.id AS mut_id,
            t1.id AS st_id,
            t2.id AS mp_id,
            t3.id AS file_id,
            (SELECT count(*) FROM %s WHERE nomut.mp_id = t2.id) as nomut
            FROM %s t0, %s t1, %s t2, %s t3
            WHERE
            t0.mp_id = t2.id AND
            t0.st_id = t1.id AND
            t2.file_id = t3.id";
        db.run(format!src_metadata_sql(srcMetadataTable, nomutTable,
                mutationTable, mutationStatusTable, mutationPointTable, filesTable));

        static immutable nomut_data_tbl = "INSERT INTO %s
            SELECT
                t0.id as mut_id,
                t0.mp_id as mp_id,
                t1.line as line,
                t1.tag as tag,
                t1.comment as comment
                FROM %s t0, %s t1, %s t2
                WHERE
                t0.mp_id = t2.mp_id AND
                t1.line = t2.line";
        db.run(format!nomut_data_tbl(nomutDataTable, mutationTable,
                rawSrcMetadataTable, nomutTable));
    }
}

struct DbTestFile {
    private Miniorm* db_;

    scope ref Miniorm db() return @safe {
        return *db_;
    }

    void put(const TestFile tfile) @trusted {
        static immutable sql = format!"INSERT OR IGNORE INTO %s (path, checksum0, checksum1, timestamp)
            VALUES (:path, :checksum0, :checksum1, :timestamp)"(testFilesTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":path", tfile.file.get.toString);
        stmt.get.bind(":checksum0", cast(long) tfile.checksum.get.c0);
        stmt.get.bind(":checksum1", cast(long) tfile.checksum.get.c1);
        stmt.get.bind(":timestamp", tfile.timeStamp.toSqliteDateTime);
        stmt.get.execute;
    }

    TestFile[] getTestFiles() @trusted {
        static immutable sql = "SELECT path,checksum0,checksum1,timestamp FROM " ~ testFilesTable;
        auto stmt = db.prepare(sql);
        auto res = stmt.get.execute;

        auto app = appender!(TestFile[]);
        foreach (ref r; res) {
            app.put(TestFile(TestFilePath(Path(r.peek!string(0))),
                    TestFileChecksum(Checksum(r.peek!long(1), r.peek!long(2))),
                    r.peek!string(3).fromSqLiteDateTime));
        }

        return app.data;
    }

    /// Returns: the oldest test file, if it exists.
    Optional!TestFile getNewestTestFile() @trusted {
        auto stmt = db.prepare("SELECT path,checksum0,checksum1,timestamp
            FROM " ~ testFilesTable ~ " ORDER BY datetime(timestamp) DESC LIMIT 1");
        auto res = stmt.get.execute;

        foreach (ref r; res) {
            return some(TestFile(TestFilePath(Path(r.peek!string(0))),
                    TestFileChecksum(Checksum(r.peek!long(1), r.peek!long(2))),
                    r.peek!string(3).fromSqLiteDateTime));
        }

        return none!TestFile;
    }

    /// Remove the file with all mutations that are coupled to it.
    void removeFile(const TestFilePath p) @trusted {
        auto stmt = db.prepare("DELETE FROM " ~ testFilesTable ~ " WHERE path=:path");
        stmt.get.bind(":path", p.get.toString);
        stmt.get.execute;
    }
}

private:

MarkedMutant make(MarkedMutantTbl m) {
    import dextool.plugin.mutate.backend.type;

    return MarkedMutant(m.mutationStatusId.MutationStatusId, Checksum(m.checksum0,
            m.checksum1), m.mutationId.MutationId, SourceLoc(m.line, m.column),
            m.path.Path, m.toStatus.to!(Mutation.Status), m.time,
            m.rationale.Rationale, m.mutText);
}

string fromOrder(const MutationOrder userOrder) {
    final switch (userOrder) {
    case MutationOrder.random:
        return ":base_prio + t1.prio + abs(random() % 100)";
    case MutationOrder.consecutive:
        return ":base_prio";
    case MutationOrder.bySize:
        return ":base_prio + t1.prio";
    }
}
