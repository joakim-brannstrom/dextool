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

ExitStatusType runAdmin(ref Database db, AdminOperation admin_op,
        MutationKind[] mutations, Mutation.Status status, Mutation.Status to_status) @safe nothrow {
    import dextool.plugin.mutate.backend.utility;

    const auto kinds = dextool.plugin.mutate.backend.utility.toInternal(mutations);

    final switch (admin_op) {
    case AdminOperation.reset:
        return resetMutant(db, kinds, status, to_status);
    case AdminOperation.remove:
        return removeMutant(db, kinds);
    }
}

private:

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
