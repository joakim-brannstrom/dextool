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
import dextool.plugin.mutate.backend.type : Mutation, Offset;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.generate_mutant : makeMutationText;

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
        FilesysIO fio;
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

    auto markMutantData(long v, string s, FilesysIO f) {
        data.mutant_id = v;
        data.mutant_rationale = s;
        data.fio = f;
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
            return markMutant(db, data.mutant_id, data.kinds,
                    data.to_status, data.mutant_rationale, data.fio);
        case AdminOperation.removeMarkedMutant:
            return removeMarkedMutant(db, data.mutant_id);
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

ExitStatusType markMutant(ref Database db, MutationId id, const Mutation.Kind[] kinds,
        Mutation.Status status, string rationale, FilesysIO fio) @trusted nothrow {
    try {
        import std.conv : to;
        auto trans = db.transaction;

        const st_id = db.getMutationStatusId(id);
        if (st_id.isNull) {
            logger.errorf("Failure when marking mutant: %s", id);
        } else {
            auto mut = db.getMutation(id);
            if (mut.isNull)
                logger.errorf("Failure when marking mutant: %s", id);
            else {
                // assume that mutant has kind
                auto txt = makeMutationText(fio.makeInput(AbsolutePath(mut.file, DirName(fio.getOutputDir))),
                        Offset(mut.sloc.line, mut.sloc.column), db.getKind(id), mut.lang).mutation;
                db.markMutant(mut, st_id.get, status, rationale, to!string(txt));
                db.updateMutationStatus(st_id.get, status);
                logger.infof(`Mutant %s marked with status %s and rationale '%s'.`, id, status, rationale);
            }
        }

        trans.commit;
    } catch (Exception e) {
        logger.error(e.msg).collectException;
        return ExitStatusType.Errors;
    }
    return ExitStatusType.Ok;
}

ExitStatusType removeMarkedMutant(ref Database db, MutationId id) @trusted nothrow {
    try {
        auto trans = db.transaction;

        // MutationStatusId used as check, removal of marking and updating status to unknown
        const st_id = db.getMutationStatusId(id);
        if (st_id.isNull) {
            logger.errorf("Failure when removing marked mutant: %s", id);
        } else {
            if (db.isMarked(id)) {
                db.removeMarkedMutant(st_id.get);
                db.updateMutationStatus(st_id.get, Mutation.Status.unknown);
                logger.infof("Removed marking for mutant %s.", id);
            } else {
                logger.errorf("Failure when removing marked mutant (mutant %s is not marked)", id);
            }
        }

        trans.commit;
    } catch (Exception e) {
        logger.error(e.msg).collectException;
        return ExitStatusType.Errors;
    }
    return ExitStatusType.Ok;
}
