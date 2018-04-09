/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains the a basic database interface that have minimal dependencies on internal modules.
It is intended to be reusable from the test suite.

The only acceptable dependency are:
 * ../type.d
 * ..backend/type.d
 * ../database/type.d
 * ../database/schema.d
*/
module dextool.plugin.mutate.backend.database.standalone;

import core.time : Duration;
import logger = std.experimental.logger;

import d2sqlite3 : sqlDatabase = Database;

import dextool.type : AbsolutePath, Path;

import dextool.plugin.mutate.backend.database.schema;
import dextool.plugin.mutate.backend.database.type;

/** Database wrapper with minimal dependencies.
 */
struct Database {
    import std.conv : to;
    import std.exception : collectException;
    import std.typecons : Nullable;
    import dextool.plugin.mutate.backend.type : MutationPoint, Mutation,
        Checksum;

    sqlDatabase* db;
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

    ~this() @trusted {
        destroy(db);
    }

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
        auto stmt = db.prepare("DELETE FROM files WHERE path=:path");
        stmt.bind(":path", cast(string) p);
        stmt.execute;
    }

    /// Returns: All files in the database as relative paths.
    Path[] getFiles() @trusted {
        import std.array : appender;

        auto stmt = db.prepare("SELECT path from files");
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
     *  bcast = mutants to broadcast the status to in addition to the id
     */
    void updateMutationBroadcast(const MutationId id, const Mutation.Status st,
            const Duration d, const(TestCase)[] tcs, const(Mutation.Kind)[] bcast) @trusted {
        import std.algorithm : map;
        import std.array : array;
        import std.format : format;

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

        stmt = db.prepare(format("SELECT id FROM mutation WHERE mp_id=:id AND kind IN (%(%s,%))",
                bcast.map!(a => cast(int) a)));
        stmt.bind(":id", mp_id);
        res = stmt.execute;

        if (res.empty)
            return;

        auto mut_ids = res.map!(a => a.peek!long(0).MutationId).array;

        stmt = db.prepare(format("UPDATE mutation SET status=:st,time=:time WHERE id IN (%(%s,%))",
                mut_ids.map!(a => cast(long) a)));
        stmt.bind(":st", st.to!long);
        stmt.bind(":time", d.total!"msecs");
        stmt.execute;

        foreach (const mut_id; mut_ids) {
            updateMutationTestCases(mut_id, tcs);
        }
    }

    Nullable!MutationEntry getMutation(const MutationId id) nothrow @trusted {
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
            auto file = Path(FileName(v.peek!string(7)));
            auto sloc = SourceLoc(v.peek!uint(5), v.peek!uint(6));

            import core.time : dur;

            rval = MutationEntry(pkey, file, sloc, mp, v.peek!long(2).dur!"msecs");
        }
        catch (Exception e) {
            logger.warning(e.msg).collectException;
        }

        return rval;
    }

    /** Remove all mutations of kinds.
     */
    void removeMutant(const Mutation.Kind[] kinds) @trusted {
        import std.algorithm : map;
        import std.format : format;

        auto s = format("DELETE FROM mutation_point WHERE id IN (SELECT mp_id FROM mutation WHERE kind IN (%(%s,%)))",
                kinds.map!(a => cast(int) a));
        auto stmt = db.prepare(s);
        stmt.execute;
    }

    /** Reset all mutations of kinds with the status `st` to unknown.
     */
    void resetMutant(const Mutation.Kind[] kinds, Mutation.Status st, Mutation.Status to_st) @trusted {
        import std.algorithm : map;
        import std.format : format;

        auto s = format("UPDATE mutation SET status=%s WHERE status == %s AND kind IN (%(%s,%))",
                to_st.to!long, st.to!long, kinds.map!(a => cast(int) a));
        auto stmt = db.prepare(s);
        stmt.execute;
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

    void put(const Path p, Checksum cs) @trusted {
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
    void put(const(MutationPointEntry)[] mps, AbsolutePath rel_dir) @trusted {
        import std.path : relativePath;

        auto mp_stmt = db.prepare("INSERT INTO mutation_point (file_id, offset_begin, offset_end, line, column) VALUES (:fid, :begin, :end, :line, :column)");
        auto m_stmt = db.prepare(
                "INSERT INTO mutation (mp_id, kind, status) VALUES (:mp_id, :kind, :status)");

        db.begin;
        scope (success)
            db.commit;
        scope (failure)
            db.rollback;

        FileId[Path] file_ids;
        foreach (a; mps) {
            // remove mutation points that would never result in a mutation
            if (a.mp.mutations.length == 0)
                continue;

            if (a.file is null) {
                debug logger.trace("this should not happen. The file is null file");
                continue;
            }
            auto rel_file = relativePath(a.file, rel_dir).Path;

            FileId id;
            // assuming it is slow to lookup in the database so cache the lookups.
            if (auto e = rel_file in file_ids) {
                id = *e;
            } else {
                auto e = getFileId(rel_file);
                if (e.isNull) {
                    // this only happens when the database is out of sync with
                    // the filesystem or absolute paths are used.
                    logger.errorf("File '%s' do not exist in the database",
                            rel_file).collectException;
                    continue;
                }
                id = e;
                file_ids[rel_file] = id;
            }

            // fails if the constraint for mutation_point is violated
            // TODO still a bit slow because this generates many exceptions.
            try {
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
            catch (Exception e) {
            }
        }
    }

    /** Add a link between the mutation and what test case killed it.
        Params:
            id = ?
            tcs = test cases to add
      */
    void updateMutationTestCases(const MutationId id, const(TestCase)[] tcs) @trusted {
        import std.format : format;

        if (tcs.length == 0)
            return;

        immutable mut_id = id.to!string;

        try {
            immutable remove_old_sql = format("DELETE FROM %s WHERE mut_id=:id", testCaseTable);
            auto stmt = db.prepare(remove_old_sql);
            stmt.bind(":id", mut_id);
            stmt.execute;
        }
        catch (Exception e) {
        }

        immutable add_new_sql = format("INSERT INTO %s (mut_id, test_case) VALUES(:mut_id, :tc)",
                testCaseTable);
        foreach (const tc; tcs) {
            try {
                auto stmt = db.prepare(add_new_sql);
                stmt.bind(":mut_id", mut_id);
                stmt.bind(":tc", cast(string) tc);
                stmt.execute;
            }
            catch (Exception e) {
                logger.warning(e.msg);
            }
        }
    }

    /** Returns: test cases that killed the mutant.
      */
    TestCase[] getTestCases(const MutationId id) @trusted {
        import std.array : Appender;
        import std.format : format;

        Appender!(TestCase[]) rval;

        immutable get_test_cases_sql = format("SELECT test_case FROM %s WHERE mut_id=:id",
                testCaseTable);
        auto stmt = db.prepare(get_test_cases_sql);
        stmt.bind(":id", cast(long) id);
        foreach (a; stmt.execute) {
            rval.put(TestCase(a.peek!string(0)));
        }

        return rval.data;
    }

    /** Returns: test cases that killed other mutants at the same mutation point as `id`.
      */
    TestCase[] getOtherTestCases(const MutationId id) @trusted {
        import std.algorithm : map;
        import std.array : Appender, array;
        import std.format : format;

        Appender!(TestCase[]) rval;

        // TODO: optimize this. should be able to merge the two first queries to one.

        long mp_id;
        {
            auto stmt = db.prepare(format("SELECT mp_id FROM %s WHERE id=:id", mutationTable));
            stmt.bind(":id", cast(long) id);
            auto res = stmt.execute;
            if (res.empty)
                return null;
            mp_id = res.oneValue!long;
        }

        long[] mut_ids;
        {
            auto stmt = db.prepare(format("SELECT id FROM %s WHERE mp_id=:id", mutationTable));
            stmt.bind(":id", mp_id);
            auto res = stmt.execute;
            if (res.empty)
                return null;
            mut_ids = res.map!(a => a.peek!long(0)).array;
        }

        immutable get_test_cases_sql = format("SELECT test_case FROM %s WHERE mut_id IN (%(%s,%))",
                testCaseTable, mut_ids);
        auto stmt = db.prepare(get_test_cases_sql);
        stmt.bind(":id", cast(long) id);
        foreach (a; stmt.execute) {
            rval.put(TestCase(a.peek!string(0)));
        }

        return rval.data;
    }

    import std.regex : Regex;

    void removeTestCase(const Regex!char rex, const(Mutation.Kind)[] kinds) @trusted {
        import std.algorithm : map;
        import std.format : format;
        import std.regex : matchFirst;

        immutable sql = format(
                "SELECT test_case.id,test_case.test_case FROM %s,%s WHERE %s.mut_id=%s.id AND %s.kind IN (%(%s,%))",
                testCaseTable, mutationTable,
                testCaseTable, mutationTable, mutationTable, kinds.map!(a => cast(long) a));
        auto stmt = db.prepare(sql);

        foreach (row; stmt.execute) {
            string tc = row.peek!string(1);
            if (tc.matchFirst(rex).empty)
                continue;

            long id = row.peek!long(0);
            auto del_stmt = db.prepare(format("DELETE FROM %s WHERE id=:id", testCaseTable));
            del_stmt.bind(":id", id);
            del_stmt.execute;
        }
    }
}
