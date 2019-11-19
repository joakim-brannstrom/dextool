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

import std.exception : collectException;
import logger = std.experimental.logger;

import dextool.type;

import dextool.plugin.mutate.type : MutationKind, AdminOperation;
import dextool.plugin.mutate.backend.database : Database, MutationId;
import dextool.plugin.mutate.backend.type : Mutation;

auto makeAdmin() {
    return BuildAdmin();
}

private:

import std.regex : regex, Regex;

struct BuildAdmin {
@safe:
nothrow:
    private struct InternalData {
        bool errorInData;

        AdminOperation admin_op;
        Mutation.Kind[] kinds;
        Mutation.Status status;
        Mutation.Status to_status;
        Regex!char test_case_regex;
        MutationId mutant_id;
        string mutant_rationale;
    }

    private InternalData data;

    auto operation(AdminOperation v) {
        data.admin_op = v;
        return this;
    }

    auto mutations(MutationKind[] v) {
        import dextool.plugin.mutate.backend.utility;

        data.kinds = toInternal(v);
        return this;
    }

    auto fromStatus(Mutation.Status v) {
        data.status = v;
        return this;
    }

    auto toStatus(Mutation.Status v) {
        data.to_status = v;
        return this;
    }

    auto testCaseRegex(string v) {
        try {
            data.test_case_regex = regex(v);
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            data.errorInData = true;
        }
        return this;
    }

    auto markMutantData(long v, string s) {
        data.mutant_id = v;
        data.mutant_rationale = s;
        return this;
    }

    ExitStatusType run(ref Database db) {
        if (data.errorInData) {
            logger.error("Invalid parameters").collectException;
            return ExitStatusType.Errors;
        }

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
            return removeTestCase(db,
                    data.kinds, data.test_case_regex);
        case AdminOperation.markMutant:
            return markMutant(db, data.mutant_id,
                    data.to_status, data.mutant_rationale);
        }
    }
}

ExitStatusType resetMutant(ref Database db, const Mutation.Kind[] kinds,
        Mutation.Status status, Mutation.Status to_status) @safe nothrow {
    try {
        db.resetMutant(kinds, status, to_status);
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

ExitStatusType removeTestCase(ref Database db, const Mutation.Kind[] kinds, const Regex!char regex) @safe nothrow {
    try {
        db.removeTestCase(regex, kinds);
    } catch (Exception e) {
        logger.error(e.msg).collectException;
        return ExitStatusType.Errors;
    }
    return ExitStatusType.Ok;
}

ExitStatusType markMutant(ref Database db, MutationId id, Mutation.Status status, string rationale) @trusted nothrow {
    try {
        auto trans = db.transaction;

        const st_id = db.getMutationStatusId(id);
        if (st_id.isNull) {
            logger.errorf("Failure when marking mutant: %s", id);
        } else {
            db.markMutant(id, st_id.get, status, rationale);
            db.updateMutationStatus(st_id.get, status);
            logger.infof(`Mutant %s marked with status %s and rationale '%s'.`, id, status, rationale);
        }

        trans.commit;
    } catch (Exception e) {
        logger.error(e.msg).collectException;
        return ExitStatusType.Errors;
    }
    return ExitStatusType.Ok;
}
