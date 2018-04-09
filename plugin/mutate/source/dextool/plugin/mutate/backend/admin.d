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
import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.type : Mutation;

auto makeAdmin() {
    return BuildAdmin();
}

private:

struct BuildAdmin {
@safe:
nothrow:
    private struct InternalData {
        AdminOperation admin_op;
        Mutation.Kind[] kinds;
        Mutation.Status status;
        Mutation.Status to_status;
        string test_case_regex;
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
        data.test_case_regex = v;
        return this;
    }

    ExitStatusType run(ref Database db) {
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
        }
    }
}

ExitStatusType resetMutant(ref Database db, const Mutation.Kind[] kinds,
        Mutation.Status status, Mutation.Status to_status) @safe nothrow {
    try {
        db.resetMutant(kinds, status, to_status);
    }
    catch (Exception e) {
        logger.error(e.msg).collectException;
        return ExitStatusType.Errors;
    }

    return ExitStatusType.Ok;
}

ExitStatusType removeMutant(ref Database db, const Mutation.Kind[] kinds) @safe nothrow {
    try {
        db.removeMutant(kinds);
    }
    catch (Exception e) {
        logger.error(e.msg).collectException;
        return ExitStatusType.Errors;
    }

    return ExitStatusType.Ok;
}

ExitStatusType removeTestCase(ref Database db, const string regex) @safe nothrow {
    return ExitStatusType.Ok;
}
