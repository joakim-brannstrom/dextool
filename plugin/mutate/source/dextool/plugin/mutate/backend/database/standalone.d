/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
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
import std.algorithm : copy, map, joiner;
import std.array : Appender, appender, array;
import std.conv : to;
import std.datetime : SysTime, Clock;
import std.exception : collectException;
import std.format : format;
import std.path : relativePath;
import std.regex : Regex, matchFirst;
import std.typecons : Nullable, Flag, No;

import miniorm : toSqliteDateTime, fromSqLiteDateTime, Bind;

import dextool.type : AbsolutePath, Path, ExitStatusType;

import dextool.plugin.mutate.backend.database.schema;
import dextool.plugin.mutate.backend.database.type;
import dextool.plugin.mutate.backend.type : Language, Checksum;

/** Database wrapper with minimal dependencies.
 */
struct Database {
    import miniorm : Miniorm, select, insert, insertOrReplace, delete_;
    import d2sqlite3 : SqlDatabase = Database;
    import dextool.plugin.mutate.backend.type : MutationPoint, Mutation, Checksum;

    Miniorm db;
    alias db this;

    /** Create a database by either opening an existing or initializing a new.
     *
     * Params:
     *  db = path to the database
     */
    static auto make(string db) @safe {
        return Database(initializeDB(db));
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

    bool exists(MutationStatusId status_id) {
        immutable s = format!"SELECT COUNT(*) FROM %s WHERE id=:id LIMIT 1"(mutationStatusTable);
        auto stmt = db.prepare(s);
        stmt.get.bind(":id", cast(long) status_id);
        auto res = stmt.get.execute;
        return res.oneValue!long == 0;
    }

    bool isMarked(MutationId id) @trusted {
        immutable s = format!"SELECT COUNT(*) FROM %s WHERE st_id IN
            (SELECT st_id FROM %s WHERE id=:id)"(
                markedMutantTable, mutationTable);
        auto stmt = db.prepare(s);
        stmt.get.bind(":id", cast(long) id);
        auto res = stmt.get.execute;
        return res.oneValue!long != 0;
    }

    /// All marked mutants whom have a mutation status checksum that has been removed from the database.
    MarkedMutant[] getLostMarkings() @trusted {
        immutable sql = format!"SELECT checksum0 FROM %s
            WHERE
            checksum0 NOT IN (SELECT checksum0 FROM %s)"(
                markedMutantTable, mutationStatusTable);

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

    Nullable!FileId getFileId(const Path p) @trusted {
        enum sql = format("SELECT id FROM %s WHERE path=:path", filesTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":path", cast(string) p);
        auto res = stmt.get.execute;

        typeof(return) rval;
        if (!res.empty)
            rval = FileId(res.oneValue!long);
        return rval;
    }

    /// Returns: the path ID for the mutant.
    Nullable!FileId getFileId(const MutationId id) @trusted {
        enum sql = format("SELECT t1.file_id
            FROM %s t0, %s t1
            WHERE t0.id = :id AND t0.mp_id = t1.id",
                    mutationTable, mutationPointTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", cast(long) id);

        typeof(return) rval;
        foreach (r; stmt.get.execute)
            rval = FileId(r.peek!long(0));
        return rval;
    }

    /// Returns: the file path that the id correspond to.
    Nullable!Path getFile(const FileId id) @trusted {
        enum sql = format("SELECT path FROM %s WHERE id = :id", filesTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", cast(long) id);

        typeof(return) rval;
        foreach (r; stmt.get.execute)
            rval = Path(r.peek!string(0));
        return rval;
    }

    /// Remove the file with all mutations that are coupled to it.
    void removeFile(const Path p) @trusted {
        auto stmt = db.prepare(format!"DELETE FROM %s WHERE path=:path"(filesTable));
        stmt.get.bind(":path", cast(string) p);
        stmt.get.execute;
    }

    /// Returns: All files in the database as relative paths.
    Path[] getFiles() @trusted {
        auto stmt = db.prepare(format!"SELECT path from %s"(filesTable));
        auto res = stmt.get.execute;

        auto app = appender!(Path[]);
        foreach (ref r; res) {
            app.put(Path(r.peek!string(0)));
        }

        return app.data;
    }

    enum CntAction {
        /// Increment the counter
        incr,
        /// Reset the counter to zero
        reset,
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
    void updateMutation(const MutationId id, const Mutation.Status st,
            const Duration d, const(TestCase)[] tcs, CntAction counter = CntAction.incr) @trusted {
        enum sql = "UPDATE %s SET
            status=:st,time=:time,update_ts=:update_ts,%s
            WHERE
            id IN (SELECT st_id FROM %s WHERE id = :id)";

        auto stmt = () {
            final switch (counter) {
            case CntAction.incr:
                return db.prepare(format!sql(mutationStatusTable,
                        "test_cnt=test_cnt+1", mutationTable));
            case CntAction.reset:
                return db.prepare(format!sql(mutationStatusTable,
                        "test_cnt=0", mutationTable));
            }
        }();

        stmt.get.bind(":st", st.to!long);
        stmt.get.bind(":id", id.to!long);
        stmt.get.bind(":time", d.total!"msecs");
        stmt.get.bind(":update_ts", Clock.currTime.toUTC.toSqliteDateTime);
        stmt.get.execute;

        updateMutationTestCases(id, tcs);
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
    void updateMutation(const MutationStatusId id, const Mutation.Status st,
            const Duration d, CntAction counter = CntAction.incr) @trusted {
        enum sql = "UPDATE %s SET
            status=:st,time=:time,update_ts=:update_ts,%s
            WHERE
            id = :id";

        auto stmt = () {
            final switch (counter) {
            case CntAction.incr:
                return db.prepare(format!sql(mutationStatusTable,
                        "test_cnt=test_cnt+1"));
            case CntAction.reset:
                return db.prepare(format!sql(mutationStatusTable, "test_cnt=0"));
            }
        }();

        stmt.get.bind(":id", cast(long) id);
        stmt.get.bind(":st", cast(long) st);
        stmt.get.bind(":time", d.total!"msecs");
        stmt.get.bind(":update_ts", Clock.currTime.toUTC.toSqliteDateTime);
        stmt.get.execute;
    }

    /** Update the counter of how many times the mutants has been alive.
     *
     * Params:
     *  id = ID of the mutant
     *  counter = how to act with the counter
     */
    void updateMutation(const MutationStatusId id, const CntAction counter) @trusted {
        enum sql = "UPDATE %s SET %s WHERE id = :id";

        auto stmt = () {
            final switch (counter) {
            case CntAction.incr:
                return db.prepare(format!sql(mutationStatusTable,
                        "test_cnt=test_cnt+1"));
            case CntAction.reset:
                return db.prepare(format!sql(mutationStatusTable, "test_cnt=0"));
            }
        }();

        stmt.get.bind(":id", id.to!long);
        stmt.get.execute;
    }

    /// Update the time used to test the mutant.
    void updateMutation(const MutationStatusId id, const Duration testTime) @trusted {
        enum sql = format!"UPDATE %s SET time=:time WHERE id = :id"(mutationStatusTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", id.to!long);
        stmt.get.bind(":time", testTime.total!"msecs");
        stmt.get.execute;
    }

    /** Update the status of a mutant.
     *
     * Params:
     *  id = mutation status ID
     *  st = new status
     *  update_ts = if the update timestamp should be updated.
     */
    void updateMutationStatus(const MutationStatusId id, const Mutation.Status st,
            Flag!"updateTs" update_ts = No.updateTs) @trusted {

        auto stmt = () {
            if (update_ts) {
                const ts = Clock.currTime.toUTC.toSqliteDateTime;
                auto s = db.prepare(format!"UPDATE %s SET status=:st,update_ts=:update_ts WHERE id=:id"(
                        mutationStatusTable));
                s.get.bind(":update_ts", ts);
                return s;
            } else
                return db.prepare(format!"UPDATE %s SET status=:st WHERE id=:id"(
                        mutationStatusTable));
        }();
        stmt.get.bind(":st", st.to!long);
        stmt.get.bind(":id", id.to!long);
        stmt.get.execute;
    }

    /// Returns: all mutation status IDs.
    MutationStatusId[] getAllMutationStatus() @trusted {
        enum sql = format!"SELECT id FROM %s"(mutationStatusTable);

        auto app = appender!(MutationStatusId[])();
        auto stmt = db.prepare(sql);
        foreach (r; stmt.get.execute)
            app.put(MutationStatusId(r.peek!long(0)));
        return app.data;
    }

    Nullable!(Mutation.Status) getMutationStatus(const MutationStatusId id) @trusted {
        enum sql = format!"SELECT status FROM %s WHERE id=:id"(mutationStatusTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", cast(long) id);

        typeof(return) rval;
        foreach (a; stmt.get.execute) {
            rval = cast(Mutation.Status) a.peek!long(0);
        }
        return rval;
    }

    Nullable!MutationEntry getMutation(const MutationId id) @trusted {
        import dextool.plugin.mutate.backend.type;

        typeof(return) rval;

        enum get_mut_sql = format("SELECT
            t0.id,
            t0.kind,
            t3.time,
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
            ", mutationTable, mutationPointTable,
                    filesTable, mutationStatusTable);

        auto stmt = db.prepare(get_mut_sql);
        stmt.get.bind(":id", cast(long) id);
        auto res = stmt.get.execute;

        if (res.empty)
            return rval;

        auto v = res.front;

        auto mp = MutationPoint(Offset(v.peek!uint(3), v.peek!uint(4)));
        mp.mutations = [Mutation(v.peek!long(1).to!(Mutation.Kind))];
        auto pkey = MutationId(v.peek!long(0));
        auto file = Path(v.peek!string(7));
        auto sloc = SourceLoc(v.peek!uint(5), v.peek!uint(6));
        auto lang = v.peek!long(8).to!Language;

        rval = MutationEntry(pkey, file, sloc, mp, v.peek!long(2).dur!"msecs", lang);

        return rval;
    }

    MutantMetaData getMutantationMetaData(const MutationId id) @trusted {
        auto rval = MutantMetaData(id);
        foreach (res; db.run(select!NomutDataTbl.where("mut_id = :mutid",
                Bind("mutid")), cast(long) id)) {
            rval.set(NoMut(res.tag, res.comment));
        }
        return rval;
    }

    //TODO: this is a bit inefficient. it should use a callback iterator
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
        t.mut_id"(nomutDataTable, mutationTable,
                mutationStatusTable, kinds.map!(a => cast(long) a));
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
        enum get_path_sql = format("SELECT t2.path
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

    /// Returns: the mutants that are connected to the mutation statuses.
    MutantInfo[] getMutantsInfo(const Mutation.Kind[] kinds, const(MutationStatusId)[] id) @trusted {
        const get_mutid_sql = format("SELECT t0.id,t2.status,t0.kind,t1.line,t1.column
            FROM %s t0,%s t1, %s t2
            WHERE
            t0.st_id IN (%(%s,%)) AND
            t0.st_id = t2.id AND
            t0.kind IN (%(%s,%)) AND
            t0.mp_id = t1.id",
                mutationTable, mutationPointTable,
                mutationStatusTable, id.map!(a => cast(long) a), kinds.map!(a => cast(int) a));
        auto stmt = db.prepare(get_mutid_sql);

        auto app = appender!(MutantInfo[])();
        foreach (res; stmt.get.execute)
            app.put(MutantInfo(MutationId(res.peek!long(0)), res.peek!long(1)
                    .to!(Mutation.Status), res.peek!long(2).to!(Mutation.Kind),
                    SourceLoc(res.peek!uint(3), res.peek!uint(4))));

        return app.data;
    }

    /// Returns: the mutants that are connected to the mutation statuses.
    MutationId[] getMutationIds(const(Mutation.Kind)[] kinds, const(MutationStatusId)[] id) @trusted {
        if (id.length == 0)
            return null;

        const get_mutid_sql = format!"SELECT id FROM %s t0
            WHERE
            t0.st_id IN (%(%s,%)) AND
            t0.kind IN (%(%s,%))"(mutationTable,
                id.map!(a => cast(long) a), kinds.map!(a => cast(int) a));
        auto stmt = db.prepare(get_mutid_sql);

        auto app = appender!(MutationId[])();
        foreach (res; stmt.get.execute)
            app.put(MutationId(res.peek!long(0)));
        return app.data;
    }

    Nullable!MutationId getMutationId(const MutationStatusId id) @trusted {
        immutable sql = format!"SELECT id FROM %s WHERE st_id=:st_id"(mutationTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":st_id", cast(long) id);

        typeof(return) rval;
        foreach (res; stmt.get.execute) {
            rval = res.peek!long(0).MutationId;
            break;
        }
        return rval;
    }

    Nullable!MutationStatusId getMutationStatusId(const MutationId id) @trusted {
        immutable sql = format!"SELECT st_id FROM %s WHERE id=:id"(mutationTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", cast(long) id);

        typeof(return) rval;
        foreach (res; stmt.get.execute) {
            rval = MutationStatusId(res.peek!long(0));
        }
        return rval;
    }

    Nullable!MutationStatusId getMutationStatusId(const Checksum cs) @trusted {
        immutable sql = format!"SELECT st_id FROM %s WHERE checksum0=:cs0 AND checksum1=:cs1"(
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
                    (:line BETWEEN t2.line AND t2.line_end)
                    ",
                mutationStatusTable, mutationTable, mutationPointTable,
                kinds.map!(a => cast(int) a));
        auto stmt = db.prepare(sql);
        stmt.get.bind(":fid", cast(long) fid);
        stmt.get.bind(":line", sloc.line);

        auto app = appender!(typeof(return))();
        foreach (res; stmt.get.execute)
            app.put(MutationStatusId(res.peek!long(0)));
        return app.data;
    }

    LineMetadata getLineMetadata(const FileId fid, const SourceLoc sloc) @trusted {
        // TODO: change this select to using microrm
        enum sql = format("SELECT nomut,tag,comment FROM %s
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

    /// Returns: the `nr` mutants that where the longst since they where tested.
    MutationStatusTime[] getOldestMutants(const(Mutation.Kind)[] kinds, const long nr) @trusted {
        const sql = format("SELECT t0.id,t0.update_ts FROM %s t0, %s t1
                    WHERE
                    t0.update_ts IS NOT NULL AND
                    t1.st_id = t0.id AND
                    t1.kind IN (%(%s,%))
                    ORDER BY t0.update_ts ASC LIMIT :limit",
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
    MutationStatus[] getHardestToKillMutant(const(Mutation.Kind)[] kinds,
            const Mutation.Status status, const long nr) @trusted {
        const sql = format("SELECT t0.id,t0.status,t0.test_cnt,t0.update_ts,t0.added_ts
            FROM %s t0, %s t1
            WHERE
            t0.update_ts IS NOT NULL AND
            t0.status = :status AND
            t1.st_id = t0.id AND
            t1.kind IN (%(%s,%)) AND
            t1.st_id NOT IN (SELECT st_id FROM %s WHERE nomut != 0)
            ORDER BY
            t0.test_cnt DESC,
            t0.added_ts ASC,
            t0.update_ts ASC
            LIMIT :limit",
                mutationStatusTable, mutationTable, kinds.map!(a => cast(int) a), srcMetadataTable);
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
                res.peek!long(2).MutantTestCount,
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

    /** Mark a mutant with status and rationale (also adds metadata).
     */
    void markMutant(const MutationId id, const Path file, const SourceLoc sloc,
            const MutationStatusId st_id, const Checksum cs,
            const Mutation.Status s, const Rationale r, string mutationTxt) @trusted {
        db.run(insertOrReplace!MarkedMutantTbl, MarkedMutantTbl(cs.c0, cs.c1,
                st_id, id, sloc.line, sloc.column, file, s, Clock.currTime.toUTC, r, mutationTxt));
    }

    void removeMarkedMutant(const Checksum cs) @trusted {
        db.run(delete_!MarkedMutantTbl.where("checksum0 = :cs0", Bind("cs0")), cast(long) cs.c0);
    }

    void removeMarkedMutant(const MutationStatusId id) @trusted {
        db.run(delete_!MarkedMutantTbl.where("st_id = :st_id", Bind("st_id")), cast(long) id);
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

    Mutation.Kind getKind(MutationId id) @trusted {
        immutable s = format!"SELECT kind FROM %s WHERE id=:id"(mutationTable);
        auto stmt = db.prepare(s);
        stmt.get.bind(":id", cast(long) id);

        typeof(return) rval;
        foreach (res; stmt.get.execute) {
            rval = res.peek!long(0).to!(Mutation.Kind);
        }
        return rval;
    }

    import dextool.plugin.mutate.backend.type;

    alias aliveMutants = countMutants!([Mutation.Status.alive], false);
    alias killedMutants = countMutants!([Mutation.Status.killed], false);
    alias timeoutMutants = countMutants!([Mutation.Status.timeout], false);

    /// Returns: Total that should be counted when calculating the mutation score.
    alias totalMutants = countMutants!([
            Mutation.Status.alive, Mutation.Status.killed, Mutation.Status.timeout
            ], false);

    alias unknownMutants = countMutants!([Mutation.Status.unknown], false);
    alias killedByCompilerMutants = countMutants!([
            Mutation.Status.killedByCompiler
            ], false);

    alias aliveSrcMutants = countMutants!([Mutation.Status.alive], true);
    alias killedSrcMutants = countMutants!([Mutation.Status.killed], true);
    alias timeoutSrcMutants = countMutants!([Mutation.Status.timeout], true);

    /// Returns: Total that should be counted when calculating the mutation score.
    alias totalSrcMutants = countMutants!([
            Mutation.Status.alive, Mutation.Status.killed, Mutation.Status.timeout
            ], true);

    alias unknownSrcMutants = countMutants!([Mutation.Status.unknown], true);
    alias killedByCompilerSrcMutants = countMutants!([
            Mutation.Status.killedByCompiler
            ], true);

    /** Count the mutants with the nomut metadata.
     *
     * Params:
     *  status = status the mutants must be in to be counted.
     *  distinc = count based on unique source code changes.
     *  kinds = the kind of mutants to count.
     *  file = file to count mutants in.
     */
    private MutationReportEntry countMutants(int[] status, bool distinct)(
            const Mutation.Kind[] kinds, string file = null) @trusted {
        static if (distinct) {
            auto qq = "
                SELECT count(*),sum(time)
                FROM (
                SELECT count(*),sum(t1.time) time
                FROM %s t0, %s t1%s
                WHERE
                %s
                t0.st_id = t1.id AND
                t1.status IN (%(%s,%)) AND
                t0.kind IN (%(%s,%))
                GROUP BY t1.id)";
        } else {
            auto qq = "
                SELECT count(*),sum(t1.time) time
                FROM %s t0, %s t1%s
                WHERE
                %s
                t0.st_id = t1.id AND
                t1.status IN (%(%s,%)) AND
                t0.kind IN (%(%s,%))";
        }
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
        if (!res.empty)
            rval = MutationReportEntry(res.front.peek!long(0),
                    res.front.peek!long(1).dur!"msecs");
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
    alias aliveNoMutSrcMutants = countNoMutMutants!([Mutation.Status.alive], true);

    /// Returns: mutants killed by the test case.
    MutationStatusId[] testCaseKilledSrcMutants(const Mutation.Kind[] kinds, TestCase tc) @trusted {
        const query = format("
            SELECT t1.id
            FROM %s t0, %s t1, %s t2, %s t3
            WHERE
            t0.st_id = t1.id AND
            t1.status = :st AND
            t0.kind IN (%(%s,%)) AND
            t2.name = :name AND
            t2.id = t3.tc_id AND
            t3.st_id = t1.id
            GROUP BY t1.id", mutationTable, mutationStatusTable,
                allTestCaseTable, killedTestCaseTable, kinds.map!(a => cast(int) a));

        auto stmt = db.prepare(query);
        stmt.get.bind(":st", cast(long) Mutation.Status.killed);
        stmt.get.bind(":name", tc.name);

        auto app = appender!(MutationStatusId[])();
        foreach (res; stmt.get.execute)
            app.put(MutationStatusId(res.peek!long(0)));

        return app.data;
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

    Nullable!Checksum getChecksum(MutationStatusId id) @trusted {
        immutable sql = format!"SELECT checksum0, checksum1 FROM %s WHERE id=:id"(
                mutationStatusTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", cast(long) id);

        typeof(return) rval;
        foreach (res; stmt.get.execute) {
            rval = Checksum(res.peek!long(0), res.peek!long(1));
            break;
        }
        return rval;
    }

    Nullable!Checksum getFileChecksum(const Path p) @trusted {
        immutable sql = format!"SELECT checksum0,checksum1 FROM %s WHERE path=:path"(filesTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":path", cast(string) p);
        auto res = stmt.get.execute;

        typeof(return) rval;
        if (!res.empty) {
            rval = Checksum(res.front.peek!long(0), res.front.peek!long(1));
        }

        return rval;
    }

    void put(const Path p, Checksum cs, const Language lang) @trusted {
        immutable sql = format!"INSERT OR IGNORE INTO %s (path, checksum0, checksum1, lang)
            VALUES (:path, :checksum0, :checksum1, :lang)"(
                filesTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":path", cast(string) p);
        stmt.get.bind(":checksum0", cast(long) cs.c0);
        stmt.get.bind(":checksum1", cast(long) cs.c1);
        stmt.get.bind(":lang", cast(long) lang);
        stmt.get.execute;
    }

    /// Remove all metadata.
    void clearMetadata() {
        immutable sql = format!"DELETE FROM %s"(rawSrcMetadataTable);
        db.run(sql);
    }

    /** Save line metadata to the database which is used to associate line
     * metadata with mutants.
     */
    void put(const LineMetadata[] mdata) {
        import sumtype;

        // TODO: convert to microrm
        enum sql = format!"INSERT OR IGNORE INTO %s
            (file_id, line, nomut, tag, comment)
            VALUES(:fid, :line, :nomut, :tag, :comment)"(
                    rawSrcMetadataTable);

        auto stmt = db.prepare(sql);
        foreach (meta; mdata) {
            auto nomut = meta.attr.match!((NoMetadata a) => NoMut.init, (NoMut a) => a);
            stmt.get.bindAll(cast(long) meta.id, meta.line, meta.isNoMut,
                    nomut.tag, nomut.comment);
            stmt.get.execute;
            stmt.get.reset;
        }
    }

    /// Store all found mutants.
    void put(MutationPointEntry2[] mps, AbsolutePath rel_dir) @trusted {
        enum insert_mp_sql = format("INSERT OR IGNORE INTO %s
            (file_id, offset_begin, offset_end, line, column, line_end, column_end)
            SELECT id,:begin,:end,:line,:column,:line_end,:column_end
            FROM %s
            WHERE
            path = :path", mutationPointTable, filesTable);
        auto mp_stmt = db.prepare(insert_mp_sql);

        foreach (mp; mps) {
            auto rel_file = relativePath(mp.file, rel_dir).Path;
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

        enum insert_cmut_sql = format("INSERT OR IGNORE INTO %s
            (status,test_cnt,update_ts,added_ts,checksum0,checksum1)
            VALUES(:st,0,:update_ts,:added_ts,:c0,:c1)",
                    mutationStatusTable);
        auto cmut_stmt = db.prepare(insert_cmut_sql);
        const ts = Clock.currTime.toUTC.toSqliteDateTime;
        cmut_stmt.get.bind(":st", Mutation.Status.unknown);
        cmut_stmt.get.bind(":update_ts", ts);
        cmut_stmt.get.bind(":added_ts", ts);
        foreach (cm; mps.map!(a => a.cms).joiner) {
            cmut_stmt.get.bind(":c0", cast(long) cm.id.c0);
            cmut_stmt.get.bind(":c1", cast(long) cm.id.c1);
            cmut_stmt.get.execute;
            cmut_stmt.get.reset;
        }

        enum insert_m_sql = format("INSERT OR IGNORE INTO %s
            (mp_id, st_id, kind)
            SELECT t0.id,t1.id,:kind FROM %s t0, %s t1, %s t2 WHERE
            t2.path = :path AND
            t0.file_id = t2.id AND
            t0.offset_begin = :off_begin AND
            t0.offset_end = :off_end AND
            t1.checksum0 = :c0 AND
            t1.checksum1 = :c1", mutationTable,
                    mutationPointTable, mutationStatusTable, filesTable);
        auto insert_m = db.prepare(insert_m_sql);

        foreach (mp; mps) {
            foreach (m; mp.cms) {
                auto rel_file = relativePath(mp.file, rel_dir).Path;
                insert_m.get.bind(":path", cast(string) rel_file);
                insert_m.get.bind(":off_begin", mp.offset.begin);
                insert_m.get.bind(":off_end", mp.offset.end);
                insert_m.get.bind(":c0", cast(long) m.id.c0);
                insert_m.get.bind(":c1", cast(long) m.id.c1);
                insert_m.get.bind(":kind", m.mut.kind);
                insert_m.get.execute;
                insert_m.get.reset;
            }
        }
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
        enum sql = format!"DELETE FROM %s"(mutationPointTable);
        db.run(sql);
    }

    /// ditto
    void removeAllFiles() @trusted {
        enum sql = format!"DELETE FROM %s"(filesTable);
        db.run(sql);
    }

    /// Remove mutants that have no connection to a mutation point, orphened mutants.
    void removeOrphanedMutants() @trusted {
        enum sql = format!"DELETE FROM %s WHERE id NOT IN (SELECT st_id FROM %s)"(
                    mutationStatusTable, mutationTable);
        db.run(sql);
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

        immutable st_id = () {
            enum st_id_for_mutation_q = format!"SELECT st_id FROM %s WHERE id=:id"(mutationTable);
            auto stmt = db.prepare(st_id_for_mutation_q);
            stmt.get.bind(":id", cast(long) id);
            return stmt.get.execute.oneValue!long;
        }();
        updateMutationTestCases(MutationStatusId(st_id), tcs);
    }

    /** Add a link between the mutation and what test case killed it.
     *
     * Params:
     *  id = ?
     *  tcs = test cases to add
     */
    void updateMutationTestCases(const MutationStatusId st_id, const(TestCase)[] tcs) @trusted {
        if (tcs.length == 0)
            return;

        try {
            enum remove_old_sql = format!"DELETE FROM %s WHERE st_id=:id"(killedTestCaseTable);
            auto stmt = db.prepare(remove_old_sql);
            stmt.get.bind(":id", cast(long) st_id);
            stmt.get.execute;
        } catch (Exception e) {
        }

        enum add_if_non_exist_tc_sql = format!"INSERT INTO %s (name) SELECT :name1 WHERE NOT EXISTS (SELECT * FROM %s WHERE name = :name2)"(
                    allTestCaseTable, allTestCaseTable);
        auto stmt_insert_tc = db.prepare(add_if_non_exist_tc_sql);

        enum add_new_sql = format!"INSERT INTO %s (st_id, tc_id, location) SELECT :st_id,t1.id,:loc FROM %s t1 WHERE t1.name = :tc"(
                    killedTestCaseTable, allTestCaseTable);
        auto stmt_insert = db.prepare(add_new_sql);
        foreach (const tc; tcs) {
            try {
                stmt_insert_tc.get.reset;
                stmt_insert_tc.get.bind(":name1", tc.name);
                stmt_insert_tc.get.bind(":name2", tc.name);
                stmt_insert_tc.get.execute;

                stmt_insert.get.reset;
                stmt_insert.get.bind(":st_id", cast(long) st_id);
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
        if (tcs.length == 0)
            return null;

        auto mut_status_ids = appender!(MutationStatusId[])();

        immutable tmp_name = "tmp_new_tc_" ~ __LINE__.to!string;
        internalAddDetectedTestCases(tcs, tmp_name);

        immutable mut_st_id = format!"SELECT DISTINCT t1.st_id
            FROM %s t0, %s t1
            WHERE
            t0.name NOT IN (SELECT name FROM %s) AND
            t0.id = t1.tc_id"(allTestCaseTable,
                killedTestCaseTable, tmp_name);
        auto stmt = db.prepare(mut_st_id);
        foreach (res; stmt.get.execute)
            mut_status_ids.put(res.peek!long(0).MutationStatusId);

        immutable remove_old_sql = format!"DELETE FROM %s WHERE name NOT IN (SELECT name FROM %s)"(
                allTestCaseTable, tmp_name);
        db.run(remove_old_sql);

        db.run(format!"DROP TABLE %s"(tmp_name));

        return mut_status_ids.data;
    }

    /** Add test cases to those that have been detected.
     *
     * They will be added if they are unique.
     */
    void addDetectedTestCases(const(TestCase)[] tcs) @trusted {
        if (tcs.length == 0)
            return;

        immutable tmp_name = "tmp_new_tc_" ~ __LINE__.to!string;
        internalAddDetectedTestCases(tcs, tmp_name);
        db.run(format!"DROP TABLE %s"(tmp_name));
    }

    /// ditto.
    private void internalAddDetectedTestCases(const(TestCase)[] tcs, string tmp_tbl) @trusted {
        db.run(format!"CREATE TEMP TABLE %s (id INTEGER PRIMARY KEY, name TEXT NOT NULL)"(
                tmp_tbl));

        immutable add_tc_sql = format!"INSERT INTO %s (name) VALUES(:name)"(tmp_tbl);
        auto insert_s = db.prepare(add_tc_sql);
        foreach (tc; tcs) {
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
        immutable add_missing_sql = format!"INSERT INTO %s (name) SELECT t1.name FROM %s t1 LEFT JOIN %s t2 ON t2.name = t1.name WHERE t2.name IS NULL"(
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
        enum sql = format("SELECT t1.name FROM %s t1 WHERE t1.id NOT IN (SELECT tc_id FROM %s)",
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
        immutable sql = format!"SELECT DISTINCT t1.id
            FROM %s t1, %s t2, %s t3
            WHERE
            t1.id = t2.tc_id AND
            t2.st_id == t3.st_id AND
            t3.kind IN (%(%s,%))"(allTestCaseTable,
                killedTestCaseTable, mutationTable, kinds.map!(a => cast(int) a));

        auto rval = appender!(TestCaseId[])();
        auto stmt = db.prepare(sql);
        foreach (a; stmt.get.execute)
            rval.put(TestCaseId(a.peek!long(0)));

        return rval.data;
    }

    /// Returns: the name of the test case.
    string getTestCaseName(const TestCaseId id) @trusted {
        enum sql = format!"SELECT name FROM %s WHERE id = :id"(allTestCaseTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", cast(long) id);
        auto res = stmt.get.execute;
        return res.oneValue!string;
    }

    /// Returns: stats about the test case.
    Nullable!TestCaseInfo getTestCaseInfo(const TestCase tc, const Mutation.Kind[] kinds) @trusted {
        const sql = format("SELECT sum(t2.time),count(t1.st_id)
            FROM %s t0, %s t1, %s t2, %s t3
            WHERE
            t0.name = :name AND
            t0.id = t1.tc_id AND
            t1.st_id = t2.id AND
            t2.id = t3.st_id AND
            t3.kind IN (%(%s,%))", allTestCaseTable,
                killedTestCaseTable, mutationStatusTable, mutationTable,
                kinds.map!(a => cast(int) a));
        auto stmt = db.prepare(sql);
        stmt.get.bind(":name", tc.name);

        typeof(return) rval;
        foreach (a; stmt.get.execute)
            rval = TestCaseInfo(a.peek!long(0).dur!"msecs", a.peek!long(1));
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
            if (auto v = name in data) {
                *v ~= MutationId(row.peek!long(1));
            } else {
                data[name] = [MutationId(row.peek!long(1))];
            }
        }

        auto app = appender!(TestCaseInfo2[])();
        data.byKeyValue.map!(a => TestCaseInfo2(TestCase(a.key), a.value)).copy(app);
        return app.data;
    }

    /// Returns: the test case.
    Nullable!TestCase getTestCase(const TestCaseId id) @trusted {
        enum sql = format!"SELECT name FROM %s WHERE id = :id"(allTestCaseTable);
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
        enum sql = format!"SELECT id FROM %s WHERE name = :name"(allTestCaseTable);
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
            ORDER BY
            t2.id"(killedTestCaseTable,
                mutationTable, kinds.map!(a => cast(int) a));

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

        enum get_test_cases_sql = format!"SELECT t1.name,t2.location
            FROM %s t1, %s t2, %s t3
            WHERE
            t3.id = :id AND
            t3.st_id = t2.st_id AND
            t2.tc_id = t1.id"(allTestCaseTable,
                    killedTestCaseTable, mutationTable);
        auto stmt = db.prepare(get_test_cases_sql);
        stmt.get.bind(":id", cast(long) id);
        foreach (a; stmt.get.execute)
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
            stmt.get.bind(":id", cast(long) id);
            auto res = stmt.get.execute;
            if (res.empty)
                return null;
            mp_id = res.oneValue!long;
        }

        // get all the mutation status ids at the mutation point
        long[] mut_st_ids;
        {
            auto stmt = db.prepare(format!"SELECT st_id FROM %s WHERE mp_id=:id"(mutationTable));
            stmt.get.bind(":id", mp_id);
            auto res = stmt.get.execute;
            if (res.empty)
                return null;
            mut_st_ids = res.map!(a => a.peek!long(0)).array;
        }

        // get all the test cases that are killed at the mutation point
        immutable get_test_cases_sql = format!"SELECT t2.name,t1.location FROM %s t1,%s t2 WHERE t1.tc_id == t2.id AND t0.st_id IN (%(%s,%))"(
                killedTestCaseTable, allTestCaseTable, mut_st_ids);
        auto stmt = db.prepare(get_test_cases_sql);
        foreach (a; stmt.get.execute) {
            rval.put(TestCase(a.peek!string(0), a.peek!string(1)));
        }

        return rval.data;
    }

    void removeTestCase(const Regex!char rex, const(Mutation.Kind)[] kinds) @trusted {
        immutable sql = format!"SELECT t1.id,t1.name FROM %s t1,%s t2, %s t3 WHERE t1.id = t2.tc_id AND t2.st_id = t3.st_id AND t3.kind IN (%(%s,%))"(
                allTestCaseTable, killedTestCaseTable, mutationTable,
                kinds.map!(a => cast(long) a));
        auto stmt = db.prepare(sql);

        auto del_stmt = db.prepare(format!"DELETE FROM %s WHERE id=:id"(allTestCaseTable));
        foreach (row; stmt.get.execute) {
            string tc = row.peek!string(1);
            if (tc.matchFirst(rex).empty)
                continue;

            long id = row.peek!long(0);
            del_stmt.get.bind(":id", id);
            del_stmt.get.execute;
            del_stmt.get.reset;
        }
    }

    /// Returns: the context for the timeout algorithm.
    MutantTimeoutCtx getMutantTimeoutCtx() @trusted {
        foreach (res; db.run(select!MutantTimeoutCtx))
            return res;
        return MutantTimeoutCtx.init;
    }

    void putMutantTimeoutCtx(const MutantTimeoutCtx ctx) @trusted {
        db.run(delete_!MutantTimeoutCtx);
        db.run(insert!MutantTimeoutCtx.insert, ctx);
    }

    void putMutantInTimeoutWorklist(const MutationStatusId id) @trusted {
        const sql = format!"INSERT OR IGNORE INTO %s (id) VALUES (:id)"(mutantTimeoutWorklistTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", cast(long) id);
        stmt.get.execute;
    }

    /** Remove all mutants that are in the worklist that do NOT have the
     * mutation status timeout.
     */
    void reduceMutantTimeoutWorklist() @trusted {
        immutable sql = format!"DELETE FROM %1$s
            WHERE
            id IN (SELECT id FROM %2$s WHERE status != :status)"(
                mutantTimeoutWorklistTable, mutationStatusTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":status", cast(ubyte) Mutation.Status.timeout);
        stmt.get.execute;
    }

    /// Remove all mutants from the worklist.
    void clearMutantTimeoutWorklist() @trusted {
        immutable sql = format!"DELETE FROM %1$s"(mutantTimeoutWorklistTable);
        db.run(sql);
    }

    /// Returns: the number of mutants in the worklist.
    long countMutantTimeoutWorklist() @trusted {
        immutable sql = format!"SELECT count(*) FROM %1$s"(mutantTimeoutWorklistTable);
        auto stmt = db.prepare(sql);
        auto res = stmt.get.execute();
        return res.oneValue!long;
    }

    /// Changes the status of mutants in the timeout worklist to unknown.
    void resetMutantTimeoutWorklist() @trusted {
        immutable sql = format!"UPDATE %1$s SET status=:st WHERE id IN (SELECT id FROM %2$s)"(
                mutationStatusTable, mutantTimeoutWorklistTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":st", cast(ubyte) Mutation.Status.unknown);
        stmt.get.execute;
    }

    /** Update the content of metadata tables with what has been added to the
     * raw table data.
     */
    void updateMetadata() @trusted {
        db.run(format!"DELETE FROM %s"(srcMetadataTable));
        db.run(format!"DELETE FROM %s"(nomutTable));
        db.run(format!"DELETE FROM %s"(nomutDataTable));

        immutable nomut_tbl = "INSERT INTO %s
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

        immutable src_metadata_sql = "INSERT INTO %s
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

        immutable nomut_data_tbl = "INSERT INTO %s
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

    /// Returns: a random schemata from the schemata worklist.
    Nullable!Schemata nextSchemata() @trusted {
        immutable sql = format!"SELECT
            t1.path, t0.text, t0.offset_begin, t0.offset_end
            FROM %1$s t0, %2$s t1
            WHERE
            t0.schem_id = :id AND
            t0.file_id = t1.id
            ORDER BY t0.order_ ASC
            "(schemataFragmentTable, filesTable);

        Schemata schemata(long id) {
            auto stmt = db.prepare(sql);
            stmt.get.bind(":id", id);

            auto app = appender!(SchemataFragment[])();
            foreach (a; stmt.get.execute) {
                app.put(SchemataFragment(a.peek!string(0).Path,
                        Offset(a.peek!uint(2), a.peek!uint(3)), a.peek!(ubyte[])(1)));
            }

            return Schemata(SchemataId(id), app.data);
        }

        typeof(return) rval;
        auto stmt = db.prepare(
                format!"SELECT id FROM %s ORDER BY RANDOM() LIMIT 1"(schemataWorkListTable));
        foreach (a; stmt.get.execute) {
            rval = schemata(a.peek!long(0));
        }

        return rval;
    }

    MutationStatusId[] getSchemataMutants(SchemataId id) @trusted {
        immutable sql = format!"SELECT st_id FROM %s WHERE schem_id = :id"(schemataMutantTable);
        auto stmt = db.prepare(sql);
        stmt.get.bind(":id", cast(long) id);

        auto app = appender!(MutationStatusId[])();
        foreach (a; stmt.get.execute) {
            app.put(a.peek!long(0).MutationStatusId);
        }

        return app.data;
    }

    /// Mark a schemata as finished.
    void finishSchemata(SchemataId id) @trusted {
        db.run(delete_!SchemataWorkListTable.where("id = :id", Bind("id")), cast(long) id);
    }

    /// Create a schemata from a bundle of fragments.
    SchemataId putSchemata(SchemataFragment[] fragments, MutationStatusId[] mutants) @trusted {
        import std.range : enumerate;

        const schemId = () {
            immutable sql = format!"INSERT INTO %1$s VALUES(NULL)"(schemataTable);
            auto stmt = db.prepare(sql);
            stmt.get.execute;
            return db.lastInsertRowid.SchemataId;
        }();

        foreach (f; fragments.enumerate) {
            const fileId = getFileId(f.value.file);
            if (fileId.isNull) {
                logger.warning("Unable to add schemata fragment for file %s because it doesn't exist",
                        f.value.file);
                continue;
            }

            db.run(insert!SchemataFragmentTable, SchemataFragmentTable(0,
                    cast(long) schemId, cast(long) fileId.get, f.index,
                    f.value.text, f.value.offset.begin, f.value.offset.end));
        }

        // relate mutants to this schemata.
        db.run(insertOrReplace!SchemataMutantTable,
                mutants.map!(a => SchemataMutantTable(cast(long) a, cast(long) schemId)));

        db.run(insertOrReplace!SchemataWorkListTable, SchemataWorkListTable(schemId));

        return schemId;
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
