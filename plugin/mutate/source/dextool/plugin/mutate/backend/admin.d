/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains functionality to administrate the database
*/
module dextool.plugin.mutate.backend.admin;

import logger = std.experimental.logger;
import std.algorithm : filter, map;
import std.array : empty;
import std.exception : collectException;
import std.regex : matchFirst;

import dextool.type;

import dextool.plugin.mutate.type : MutationKind, AdminOperation;
import dextool.plugin.mutate.backend.database : Database, MutationStatusId;
import dextool.plugin.mutate.backend.type : Mutation, Offset, ExitStatus;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.generate_mutant : makeMutationText;

auto makeAdmin() {
    return BuildAdmin.init;
}

private:

import std.regex : regex, Regex;

struct BuildAdmin {
@safe:
    private struct InternalData {
        bool errorInData;

        AdminOperation admin_op;
        Mutation.Kind[] kinds;
        Mutation.Status status;
        Mutation.Status to_status;
        Regex!char test_case_regex;
        MutationStatusId mutant_id;
        string mutant_rationale;
        FilesysIO fio;
        AbsolutePath dbPath;
    }

    private InternalData data;

    auto database(AbsolutePath v) nothrow {
        data.dbPath = v;
        return this;
    }

    auto operation(AdminOperation v) nothrow {
        data.admin_op = v;
        return this;
    }

    auto mutations(MutationKind[] v) nothrow {
        import dextool.plugin.mutate.backend.mutation_type : toInternal;

        return mutationsSubKind(toInternal(v));
    }

    auto mutationsSubKind(Mutation.Kind[] v) nothrow {
        if (!v.empty) {
            data.kinds = v;
        }
        return this;
    }

    auto fromStatus(Mutation.Status v) nothrow {
        data.status = v;
        return this;
    }

    auto toStatus(Mutation.Status v) nothrow {
        data.to_status = v;
        return this;
    }

    auto testCaseRegex(string v) nothrow {
        try {
            data.test_case_regex = regex(v);
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            data.errorInData = true;
        }
        return this;
    }

    auto markMutantData(MutationStatusId v, string s, FilesysIO f) nothrow {
        data.mutant_id = v;
        data.mutant_rationale = s;
        data.fio = f;
        return this;
    }

    ExitStatusType run() @trusted {
        if (data.errorInData) {
            logger.error("Invalid parameters").collectException;
            return ExitStatusType.Errors;
        }

        auto db = Database.make(data.dbPath);
        return internalRun(db);
    }

    private ExitStatusType internalRun(ref Database db) {
        final switch (data.admin_op) {
        case AdminOperation.none:
            logger.error("No admin operation specified").collectException;
            return ExitStatusType.Errors;
        case AdminOperation.resetMutant:
            return resetMutant(db, data.kinds,
                    data.status, data.to_status);
        case AdminOperation.removeMutant:
            return removeMutant(db, data.kinds);
        case AdminOperation.removeTestCase:
            return removeTestCase(db, data.test_case_regex);
        case AdminOperation.resetTestCase:
            return resetTestCase(db, data.test_case_regex);
        case AdminOperation.markMutant:
            return markMutant(db, data.mutant_id,
                    data.kinds, data.to_status, data.mutant_rationale, data.fio);
        case AdminOperation.removeMarkedMutant:
            return removeMarkedMutant(db, data.mutant_id);
        case AdminOperation.compact:
            return compact(db);
        case AdminOperation.stopTimeoutTest:
            return stopTimeoutTest(db);
        case AdminOperation.resetMutantSubKind:
            return resetMutant(db,
                    data.kinds, data.status, data.to_status);
        case AdminOperation.clearWorklist:
            return clearWorklist(db);
        }
    }
}

ExitStatusType resetMutant(ref Database db, const Mutation.Kind[] kinds,
        Mutation.Status status, Mutation.Status to_status) @safe nothrow {
    try {
        logger.infof("Resetting %s with status %s to %s", kinds, status, to_status);
        db.mutantApi.resetMutant(kinds, status, to_status);
    } catch (Exception e) {
        logger.error(e.msg).collectException;
        return ExitStatusType.Errors;
    }

    return ExitStatusType.Ok;
}

ExitStatusType removeMutant(ref Database db, const Mutation.Kind[] kinds) @safe nothrow {
    try {
        db.removeMutant(kinds);
    } catch (Exception e) {
        logger.error(e.msg).collectException;
        return ExitStatusType.Errors;
    }

    return ExitStatusType.Ok;
}

ExitStatusType removeTestCase(ref Database db, const Regex!char re) @trusted nothrow {
    import std.typecons : tuple;

    try {
        auto trans = db.transaction;

        foreach (a; db.testCaseApi
                .getDetectedTestCases
                .filter!(a => !matchFirst(a.name, re).empty)
                .map!(a => tuple!("tc", "id")(a, db.testCaseApi.getTestCaseId(a)))
                .filter!(a => !a.id.isNull)) {
            logger.info("Removing ", a.tc);
            db.testCaseApi.removeTestCase(a.id.get);
        }

        trans.commit;
    } catch (Exception e) {
        logger.error(e.msg).collectException;
        return ExitStatusType.Errors;
    }

    return ExitStatusType.Ok;
}

ExitStatusType resetTestCase(ref Database db, const Regex!char re) @trusted nothrow {
    import std.typecons : tuple;

    try {
        auto trans = db.transaction;

        foreach (a; db.testCaseApi
                .getDetectedTestCases
                .filter!(a => !matchFirst(a.name, re).empty)
                .map!(a => tuple!("tc", "id")(a, db.testCaseApi.getTestCaseId(a)))
                .filter!(a => !a.id.isNull)) {
            logger.info("Resetting ", a.tc);
            db.testCaseApi.resetTestCaseId(a.id.get);
        }

        trans.commit;
    } catch (Exception e) {
        logger.error(e.msg).collectException;
        return ExitStatusType.Errors;
    }

    return ExitStatusType.Ok;
}

ExitStatusType markMutant(ref Database db, MutationStatusId id, const Mutation.Kind[] kinds,
        const Mutation.Status status, string rationale, FilesysIO fio) @trusted nothrow {
    import std.format : format;
    import std.string : strip;
    import dextool.plugin.mutate.backend.database : Rationale, toChecksum;
    import dextool.plugin.mutate.backend.report.utility : window;

    if (rationale.empty) {
        logger.error("The rationale must be set").collectException;
        return ExitStatusType.Errors;
    }

    try {
        auto trans = db.transaction;

        auto mut = db.mutantApi.getMutation(id);
        if (mut.isNull) {
            logger.errorf("Mutant with ID %s do not exist", id.get);
            return ExitStatusType.Errors;
        }

        // because getMutation worked we know the ID is valid thus no need to
        // check the return values when it or derived values are used.

        const txt = () {
            auto tmp = makeMutationText(fio.makeInput(fio.toAbsoluteRoot(mut.get.file)),
                    mut.get.mp.offset, db.mutantApi.getKind(id), mut.get.lang);
            return window(format!"'%s'->'%s'"(tmp.original.strip, tmp.mutation.strip), 30);
        }();

        db.markMutantApi.mark(mut.get.file, mut.get.sloc, id, toChecksum(id),
                status, Rationale(rationale), txt);

        db.mutantApi.update(id, status, ExitStatus(0));

        logger.infof(`Mutant %s marked with status %s and rationale %s`, id.get, status, rationale);

        trans.commit;
        return ExitStatusType.Ok;
    } catch (Exception e) {
        logger.trace(e).collectException;
        logger.error(e.msg).collectException;
    }
    return ExitStatusType.Errors;
}

ExitStatusType removeMarkedMutant(ref Database db, MutationStatusId id) @trusted nothrow {
    try {
        auto trans = db.transaction;

        // MutationStatusId used as check, removal of marking and updating status to unknown
        if (db.markMutantApi.isMarked(id)) {
            db.markMutantApi.remove(id);
            db.mutantApi.update(id, Mutation.Status.unknown, ExitStatus(0));
            logger.infof("Removed marking for mutant %s.", id);
        } else {
            logger.errorf("Failure when removing marked mutant (mutant %s is not marked)", id.get);
        }

        trans.commit;
        return ExitStatusType.Ok;
    } catch (Exception e) {
        logger.error(e.msg).collectException;
    }
    return ExitStatusType.Errors;
}

ExitStatusType compact(ref Database db) @trusted nothrow {
    try {
        logger.info("Running a SQL vacuum on the database");
        db.vacuum;
        return ExitStatusType.Ok;
    } catch (Exception e) {
        logger.error(e.msg).collectException;
    }
    return ExitStatusType.Errors;
}

ExitStatusType stopTimeoutTest(ref Database db) @trusted nothrow {
    import dextool.plugin.mutate.backend.database : Database, MutantTimeoutCtx;
    import dextool.plugin.mutate.backend.test_mutant.timeout : MaxTimeoutIterations;

    try {
        logger.info("Forcing the testing of timeout mutants to stop");
        auto t = db.transaction;

        db.timeoutApi.resetMutantTimeoutWorklist(Mutation.Status.timeout);
        db.timeoutApi.clearMutantTimeoutWorklist;
        db.worklistApi.clear;

        MutantTimeoutCtx ctx;
        ctx.iter = MaxTimeoutIterations;
        ctx.state = MutantTimeoutCtx.State.done;
        db.timeoutApi.put(ctx);

        t.commit;
        return ExitStatusType.Ok;
    } catch (Exception e) {
        logger.error(e.msg).collectException;
    }
    return ExitStatusType.Errors;
}

ExitStatusType clearWorklist(ref Database db) @trusted nothrow {
    try {
        logger.info("Clearing the mutant worklist");
        db.clearWorklist;
        return ExitStatusType.Ok;
    } catch (Exception e) {
        logger.error(e.msg).collectException;
    }
    return ExitStatusType.Errors;
}
