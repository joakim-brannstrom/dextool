/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains the a basic database interface that have minimal dependencies on internal modules.
It is intended to be reusable from the test suite.

Note that a `commit` may result in an exception.
The correct way to handle a commit that fail is to rollback. Or rather it is the easy way.
The other way would be to try the commmit at a later time.
For now though this mean that `scope(success) db.commit` should never be used.
Always use `scope(failure) db.rollback`. This ensures that a failed commit results in a rollback.
By combining this with spinSqlQuery it means that it will be retried at a later time.

The only acceptable dependency are:
 * ../type.d
 * ..backend/type.d
 * ../database/type.d
 * ../database/schema.d
*/
module dextool.plugin.mutate.backend.database.standalone;

import core.time : Duration;
import std.algorithm : map;
import std.array : Appender, appender, array;
import std.format : format;
import logger = std.experimental.logger;

import d2sqlite3 : sqlDatabase = Database;

import dextool.type : AbsolutePath, Path;

import dextool.plugin.mutate.backend.database.schema;
import dextool.plugin.mutate.backend.database.type;
import dextool.plugin.mutate.backend.type : Language;

/** Database wrapper with minimal dependencies.
 */
struct Database {
    import std.conv : to;
    import std.exception : collectException;
    import std.typecons : Nullable;
    import dextool.plugin.mutate.backend.type : MutationPoint, Mutation,
        Checksum;

    sqlDatabase db;
    alias db this;

    /** Create a database by either opening an existing or initializing a new.
     *
     * Params:
     *  db = path to the database
     */
    static auto make(string db) @safe {
        return Database(initializeDB(db));
    }

    // Not movable. The database should only be passed around as a reference,
    // if at all.
    @disable this(this);

    /// If the file has already been analyzed.
    bool isAnalyzed(const Path p) @trusted {
        auto stmt = db.prepare("SELECT count(*) FROM files WHERE path=:path LIMIT 1");
        stmt.bind(":path", cast(string) p);
        auto res = stmt.execute;
        return res.oneValue!long != 0;
    }

    /// If the file has already been analyzed.
    bool isAnalyzed(const Path p, const Checksum cs) @trusted {
        auto stmt = db.prepare(
                "SELECT count(*) FROM files WHERE path=:path AND checksum0=:cs0 AND checksum1=:cs1 LIMIT 1");
        stmt.bind(":path", cast(string) p);
        stmt.bind(":cs0", cs.c0);
        stmt.bind(":cs1", cs.c1);
        auto res = stmt.execute;
        return res.oneValue!long != 0;
    }

    Nullable!FileId getFileId(const Path p) @trusted {
        auto stmt = db.prepare("SELECT id FROM files WHERE path=:path");
        stmt.bind(":path", cast(string) p);
        auto res = stmt.execute;

        typeof(return) rval;
        if (!res.empty) {
            rval = FileId(res.oneValue!long);
        }

        return rval;
    }

    /// Remove the file with all mutations that are coupled to it.
    void removeFile(const Path p) @trusted {
        auto stmt = db.prepare(format!"DELETE FROM %s WHERE path=:path"(filesTable));
        stmt.bind(":path", cast(string) p);
        stmt.execute;
    }

    /// Returns: All files in the database as relative paths.
    Path[] getFiles() @trusted {
        auto stmt = db.prepare(format!"SELECT path from %s"(filesTable));
        auto res = stmt.execute;

        auto app = appender!(Path[]);
        foreach (ref r; res) {
            app.put(Path(r.peek!string(0)));
        }

        return app.data;
    }

    /** Update the status of a mutant.
     * Params:
     *  id = ?
     *  st = ?
     *  d = time spent on veryfing the mutant
     */
    void updateMutation(const MutationId id, const Mutation.Status st,
            const Duration d, const(TestCase)[] tcs) @trusted {
        auto stmt = db.prepare(
                "UPDATE mutation SET status=:st,time=:time WHERE mutation.id == :id");
        stmt.bind(":st", st.to!long);
        stmt.bind(":id", id.to!long);
        stmt.bind(":time", d.total!"msecs");
        stmt.execute;

        updateMutationTestCases(id, tcs);
    }

    /** Update the status of a mutant and broadcast the status to other mutants at that point.
     *
     * Params:
     *  id = mutation point is derived from this mutation ID
     *  st = status to broadcast
     *  d = mutation test time to broadcast
     *  tcs = killed test cases to broadcast
     *  bcast = mutants to broadcast the status to in addition to the id
     */
    void updateMutationBroadcast(const MutationId id, const Mutation.Status st,
            const Duration d, const(TestCase)[] tcs, const(Mutation.Kind)[] bcast) @trusted {

        if (bcast.length == 1) {
            updateMutation(id, st, d, tcs);
            return;
        }

        auto stmt = db.prepare("SELECT mp_id FROM mutation WHERE id=:id");
        stmt.bind(":id", id.to!long);
        auto res = stmt.execute;

        if (res.empty)
            return;
        long mp_id = res.front.peek!long(0);

        stmt = db.prepare(format!"SELECT id FROM mutation WHERE mp_id=:id AND kind IN (%(%s,%))"(
                bcast.map!(a => cast(int) a)));
        stmt.bind(":id", mp_id);
        res = stmt.execute;

        if (res.empty)
            return;

        auto mut_ids = res.map!(a => a.peek!long(0).MutationId).array;

        stmt = db.prepare(format!"UPDATE mutation SET status=:st,time=:time WHERE id IN (%(%s,%))"(
                mut_ids.map!(a => cast(long) a)));
        stmt.bind(":st", st.to!long);
        stmt.bind(":time", d.total!"msecs");
        stmt.execute;

        foreach (const mut_id; mut_ids) {
            updateMutationTestCases(mut_id, tcs);
        }
    }

    Nullable!MutationEntry getMutation(const MutationId id) @trusted {
        import dextool.plugin.mutate.backend.type;
        import dextool.type : FileName;

        typeof(return) rval;

        auto stmt = db.prepare("SELECT
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
        auto file = Path(FileName(v.peek!string(7)));
        auto sloc = SourceLoc(v.peek!uint(5), v.peek!uint(6));
        auto lang = v.peek!long(8).to!Language;

        import core.time : dur;

        rval = MutationEntry(pkey, file, sloc, mp, v.peek!long(2).dur!"msecs", lang);

        return rval;
    }

    /** Remove all mutations of kinds.
     */
    void removeMutant(const Mutation.Kind[] kinds) @trusted {
        auto s = format!"DELETE FROM %s WHERE id IN (SELECT mp_id FROM %s WHERE kind IN (%(%s,%)))"(
                mutationPointTable, mutationTable, kinds.map!(a => cast(int) a));
        auto stmt = db.prepare(s);
        stmt.execute;
    }

    /** Reset all mutations of kinds with the status `st` to unknown.
     */
    void resetMutant(const Mutation.Kind[] kinds, Mutation.Status st, Mutation.Status to_st) @trusted {
        auto s = format!"UPDATE mutation SET status=%s WHERE status == %s AND kind IN (%(%s,%))"(
                to_st.to!long, st.to!long, kinds.map!(a => cast(int) a));
        auto stmt = db.prepare(s);
        stmt.execute;
    }

    import dextool.plugin.mutate.backend.type;

    alias aliveMutants = countMutants!([Mutation.Status.alive]);
    alias killedMutants = countMutants!([Mutation.Status.killed]);
    alias timeoutMutants = countMutants!([Mutation.Status.timeout]);

    /// Returns: Total that should be counted when calculating the mutation score.
    alias totalMutants = countMutants!([Mutation.Status.alive,
            Mutation.Status.killed, Mutation.Status.timeout]);

    alias unknownMutants = countMutants!([Mutation.Status.unknown]);
    alias killedByCompilerMutants = countMutants!([Mutation.Status.killedByCompiler]);

    private MutationReportEntry countMutants(int[] status)(const Mutation.Kind[] kinds) @trusted {
        import core.time : dur;

        enum query = format("SELECT count(*),sum(t0.time) FROM %s t0 WHERE t0.status IN (%(%s,%)) AND t0.kind IN (%s) AND t0.st_id IN (SELECT id FROM %s GROUP BY checksum0, checksum1 HAVING count(*) = 1)",
                    mutationTable, status, "%(%s,%)", mutationStatusTable);

        typeof(return) rval;
        auto stmt = db.prepare(format(query, kinds.map!(a => cast(int) a)));
        auto res = stmt.execute;
        if (!res.empty)
            rval = MutationReportEntry(res.front.peek!long(0),
                    res.front.peek!long(1).dur!"msecs");
        return rval;
    }

    void put(const Path p, Checksum cs, const Language lang) @trusted {
        auto stmt = db.prepare("INSERT OR IGNORE INTO files (path, checksum0, checksum1, lang) VALUES (:path, :checksum0, :checksum1, :lang)");
        stmt.bind(":path", cast(string) p);
        stmt.bind(":checksum0", cast(long) cs.c0);
        stmt.bind(":checksum1", cast(long) cs.c1);
        stmt.bind(":lang", cast(long) lang);
        stmt.execute;
    }

    /// Store all found mutants.
    void put(MutationPointEntry2[] mps, AbsolutePath rel_dir) @trusted {
        import std.algorithm : map, joiner;
        import std.path : relativePath;

        db.begin;
        scope (failure)
            db.rollback;

        enum insert_mp_sql = format("INSERT OR IGNORE INTO %s (file_id, offset_begin, offset_end, line, column) SELECT id, :begin, :end, :line, :column FROM %s WHERE path = :path",
                    mutationPointTable, filesTable);
        auto mp_stmt = db.prepare(insert_mp_sql);

        foreach (mp; mps) {
            auto rel_file = relativePath(mp.file, rel_dir).Path;
            mp_stmt.bind(":begin", mp.offset.begin);
            mp_stmt.bind(":end", mp.offset.end);
            mp_stmt.bind(":line", mp.sloc.line);
            mp_stmt.bind(":column", mp.sloc.column);
            mp_stmt.bind(":path", cast(string) rel_file);
            mp_stmt.execute;
            mp_stmt.reset;
        }

        enum insert_cmut_sql = format("INSERT OR IGNORE INTO %s (status,checksum0,checksum1) VALUES(:st,:c0,:c1)",
                    mutationStatusTable);
        auto cmut_stmt = db.prepare(insert_cmut_sql);

        cmut_stmt.bind(":st", Mutation.Status.unknown);
        foreach (cm; mps.map!(a => a.cms).joiner) {
            cmut_stmt.bind(":c0", cast(long) cm.id.c0);
            cmut_stmt.bind(":c1", cast(long) cm.id.c1);
            cmut_stmt.execute;
            cmut_stmt.reset;
        }

        enum insert_m_sql = format("INSERT OR IGNORE INTO %s (mp_id, st_id, kind, status)
            SELECT t0.id,t1.id,:kind,:status FROM %s t0, %s t1, %s t2 WHERE
            t2.path = :path AND
            t0.file_id = t2.id AND
            t0.offset_begin = :off_begin AND
            t0.offset_end = :off_end AND
            t1.checksum0 = :c0 AND
            t1.checksum1 = :c1",
                    mutationTable, mutationPointTable, mutationStatusTable, filesTable);
        auto insert_m = db.prepare(insert_m_sql);

        foreach (mp; mps) {
            foreach (m; mp.cms) {
                auto rel_file = relativePath(mp.file, rel_dir).Path;
                insert_m.bind(":path", cast(string) rel_file);
                insert_m.bind(":off_begin", mp.offset.begin);
                insert_m.bind(":off_end", mp.offset.end);
                insert_m.bind(":c0", cast(long) m.id.c0);
                insert_m.bind(":c1", cast(long) m.id.c1);
                insert_m.bind(":kind", m.mut.kind);
                insert_m.bind(":status", m.mut.status);
                insert_m.execute;
                insert_m.reset;
            }
        }

        db.commit;
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
        enum del_mp_sql = format("DELETE FROM %s", mutationPointTable);
        db.run(del_mp_sql);
    }

    /// Remove mutants that have no connection to a mutation point, orphened mutants.
    void removeOrphanedMutants() @trusted {
        enum del_orp_m_sql = format("DELETE FROM %s WHERE id NOT IN (SELECT st_id FROM %s)",
                    mutationStatusTable, mutationTable);
        db.run(del_orp_m_sql);
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

        db.begin;
        scope (failure)
            db.rollback;

        immutable mut_id = cast(long) id;

        try {
            enum remove_old_sql = format("DELETE FROM %s WHERE mut_id=:id", killedTestCaseTable);
            auto stmt = db.prepare(remove_old_sql);
            stmt.bind(":id", mut_id);
            stmt.execute;
        } catch (Exception e) {
        }

        enum add_if_non_exist_tc_sql = format(
                    "INSERT INTO %s (name) SELECT :name1 WHERE NOT EXISTS (SELECT * FROM %s WHERE name = :name2)",
                    allTestCaseTable, allTestCaseTable);
        auto stmt_insert_tc = db.prepare(add_if_non_exist_tc_sql);

        enum add_new_sql = format(
                    "INSERT INTO %s (mut_id, tc_id, location) SELECT :mut_id,t1.id,:loc FROM %s t1 WHERE t1.name = :tc",
                    killedTestCaseTable, allTestCaseTable);
        auto stmt_insert = db.prepare(add_new_sql);
        foreach (const tc; tcs) {
            try {
                stmt_insert_tc.reset;
                stmt_insert_tc.bind(":name1", tc.name);
                stmt_insert_tc.bind(":name2", tc.name);
                stmt_insert_tc.execute;

                stmt_insert.reset;
                stmt_insert.bind(":mut_id", mut_id);
                stmt_insert.bind(":loc", tc.location);
                stmt_insert.bind(":tc", tc.name);
                stmt_insert.execute;
            } catch (Exception e) {
                logger.warning(e.msg);
            }
        }

        db.commit;
    }

    /** Set detected test cases.
     *
     * This will replace those that where previously stored.
     */
    void setDetectedTestCases(const(TestCase)[] tcs) @trusted {
        if (tcs.length == 0)
            return;

        db.begin;
        scope (failure)
            db.rollback;

        immutable tmp_name = "tmp_new_tc_" ~ __LINE__.to!string;
        internalAddDetectedTestCases(tcs, tmp_name);

        enum remove_old_sql = format("DELETE FROM %s WHERE name NOT IN (SELECT name FROM %s)",
                    allTestCaseTable, tmp_name);
        db.run(remove_old_sql);

        db.run(format!"DROP TABLE %s"(tmp_name));
        db.commit;
    }

    /** Add test cases to those that have been detected.
     *
     * They will be added if they are unique.
     */
    void addDetectedTestCases(const(TestCase)[] tcs) @trusted {
        if (tcs.length == 0)
            return;

        db.begin;
        scope (failure)
            db.rollback;

        immutable tmp_name = "tmp_new_tc_" ~ __LINE__.to!string;
        internalAddDetectedTestCases(tcs, tmp_name);
        db.run(format!"DROP TABLE %s"(tmp_name));
        db.commit;
    }

    /// ditto.
    private void internalAddDetectedTestCases(const(TestCase)[] tcs, string tmp_tbl) @trusted {
        db.run(format!"CREATE TEMP TABLE %s (id INTEGER PRIMARY KEY, name TEXT NOT NULL)"(
                tmp_tbl));

        immutable add_tc_sql = format!"INSERT INTO %s (name) VALUES(:name)"(tmp_tbl);
        auto insert_s = db.prepare(add_tc_sql);
        foreach (tc; tcs) {
            insert_s.bind(":name", tc.name);
            insert_s.execute;
            insert_s.reset;
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
        immutable add_missing_sql = format!"INSERT INTO %s (name) SELECT t1.name FROM %s t1 LEFT JOIN %s t2 ON t2.name = t1.name WHERE t2.name IS NULL"(
                allTestCaseTable, tmp_tbl, allTestCaseTable);
        db.run(add_missing_sql);
    }

    /// Returns: detected test cases.
    TestCase[] getDetectedTestCases() @trusted {
        enum sql = format("SELECT name FROM %s", allTestCaseTable);

        auto rval = appender!(TestCase[])();
        auto stmt = db.prepare(sql);
        foreach (a; stmt.execute) {
            rval.put(TestCase(a.peek!string(0)));
        }

        return rval.data;
    }

    /// Returns: test cases that has killed zero mutants.
    TestCase[] getTestCasesWithZeroKills() @trusted {
        enum sql = format("SELECT t1.name FROM %s t1 WHERE t1.id NOT IN (SELECT tc_id FROM %s)",
                    allTestCaseTable, killedTestCaseTable);

        auto rval = appender!(TestCase[])();
        auto stmt = db.prepare(sql);
        foreach (a; stmt.execute)
            rval.put(TestCase(a.peek!string(0)));

        return rval.data;
    }

    /** Guarantees that the there are no duplications of `TestCaseId`.
     *
     * Returns: test cases that has killed at least one mutant.
     */
    TestCaseId[] getTestCasesWithAtLeastOneKill(const Mutation.Kind[] kinds) @trusted {
        immutable sql = format!"SELECT DISTINCT t1.id FROM %s t1, %s t2, %s t3 WHERE t1.id = t2.tc_id AND t2.mut_id == t3.id AND t3.kind IN (%(%s,%))"(
                allTestCaseTable, killedTestCaseTable, mutationTable, kinds.map!(a => cast(int) a));

        auto rval = appender!(TestCaseId[])();
        auto stmt = db.prepare(sql);
        foreach (a; stmt.execute)
            rval.put(TestCaseId(a.peek!long(0)));

        return rval.data;
    }

    /// Returns: the name of the test case.
    string getTestCaseName(const TestCaseId id) @trusted {
        enum sql = format!"SELECT name FROM %s WHERE id = :id"(allTestCaseTable);
        auto stmt = db.prepare(sql);
        stmt.bind(":id", cast(long) id);
        auto res = stmt.execute;
        return res.oneValue!string;
    }

    /// Returns: the mutants the test case killed.
    MutationId[] getTestCaseMutantKills(const TestCaseId id, const Mutation.Kind[] kinds) @trusted {
        immutable sql = format!"SELECT t1.mut_id FROM %s t1, %s t2 WHERE t1.tc_id = :tid AND t1.mut_id = t2.id AND t2.kind IN (%(%s,%))"(
                killedTestCaseTable, mutationTable, kinds.map!(a => cast(int) a));

        auto rval = appender!(MutationId[])();
        auto stmt = db.prepare(sql);
        stmt.bind(":tid", cast(long) id);
        foreach (a; stmt.execute)
            rval.put(MutationId(a.peek!long(0)));

        return rval.data;
    }

    /// Returns: test cases that killed the mutant.
    TestCase[] getTestCases(const MutationId id) @trusted {
        Appender!(TestCase[]) rval;

        enum get_test_cases_sql = format!"SELECT t1.name,t2.location FROM %s t1, %s t2 WHERE t2.mut_id=:id AND t2.tc_id=t1.id"(
                    allTestCaseTable, killedTestCaseTable);
        auto stmt = db.prepare(get_test_cases_sql);
        stmt.bind(":id", cast(long) id);
        foreach (a; stmt.execute)
            rval.put(TestCase(a.peek!string(0), a.peek!string(1)));

        return rval.data;
    }

    /** Returns: number of test cases
     */
    long getNumOfTestCases() @trusted {
        enum num_test_cases_sql = format!"SELECT count(*) FROM %s"(allTestCaseTable);
        return db.execute(num_test_cases_sql).oneValue!long;
    }

    /** Returns: test cases that killed other mutants at the same mutation point as `id`.
      */
    TestCase[] getSurroundingTestCases(const MutationId id) @trusted {
        Appender!(TestCase[]) rval;

        // TODO: optimize this. should be able to merge the two first queries to one.

        // get the mutation point ID that id reside at
        long mp_id;
        {
            auto stmt = db.prepare(format!"SELECT mp_id FROM %s WHERE id=:id"(mutationTable));
            stmt.bind(":id", cast(long) id);
            auto res = stmt.execute;
            if (res.empty)
                return null;
            mp_id = res.oneValue!long;
        }

        // get all the mutation ids at the mutation point
        long[] mut_ids;
        {
            auto stmt = db.prepare(format!"SELECT id FROM %s WHERE mp_id=:id"(mutationTable));
            stmt.bind(":id", mp_id);
            auto res = stmt.execute;
            if (res.empty)
                return null;
            mut_ids = res.map!(a => a.peek!long(0)).array;
        }

        // get all the test cases that are killed at the mutation point
        immutable get_test_cases_sql = format!"SELECT t2.name,t1.location FROM %s t1,%s t2 WHERE t1.tc_id == t2.id AND mut_id IN (%(%s,%))"(
                killedTestCaseTable, allTestCaseTable, mut_ids);
        auto stmt = db.prepare(get_test_cases_sql);
        foreach (a; stmt.execute) {
            rval.put(TestCase(a.peek!string(0), a.peek!string(1)));
        }

        return rval.data;
    }

    import std.regex : Regex;

    void removeTestCase(const Regex!char rex, const(Mutation.Kind)[] kinds) @trusted {
        import std.regex : matchFirst;

        immutable sql = format!"SELECT t1.id,t1.name FROM %s t1,%s t2, %s t3 WHERE t1.id = t2.tc_id AND t2.mut_id = t3.id AND t3.kind IN (%(%s,%))"(
                allTestCaseTable, killedTestCaseTable, mutationTable,
                kinds.map!(a => cast(long) a));
        auto stmt = db.prepare(sql);

        auto del_stmt = db.prepare(format!"DELETE FROM %s WHERE id=:id"(allTestCaseTable));
        foreach (row; stmt.execute) {
            string tc = row.peek!string(1);
            if (tc.matchFirst(rex).empty)
                continue;

            long id = row.peek!long(0);
            del_stmt.reset;
            del_stmt.bind(":id", id);
            del_stmt.execute;
        }
    }
}

/** This is only intended to be used when interacting with the SQLite database.
 *
 * It spins in a loop until the query stop throwing exceptions.
 */
auto spinSqlQuery(alias Callback)() nothrow {
    import core.time : dur;
    import std.exception : collectException;
    import dextool.plugin.mutate.backend.utility : rndSleep;

    while (true) {
        try {
            return Callback();
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            // even though the database have a builtin sleep it still result in too much spam.
            rndSleep(50.dur!"msecs", 100);
        }
    }

    assert(0, "this shoud never happen");
}
