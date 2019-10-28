/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

# Analyze

The worklist should not be cleared during an analyze phase.
Any mutant that has been removed in the source code will be automatically
removed from the worklist because the tables is setup with ON DELETE CASCADE.

Thus by not removing it old timeout mutants that need more work will be
"resumed".

# Test

TODO: describe the test phase and FSM
*/
module dextool.plugin.mutate.backend.test_mutant.timeout;

import logger = std.experimental.logger;
import std.exception : collectException;
import std.typecons : Flag, NullableRef, nullableRef;

import miniorm : spinSql;

import dextool.from;
import dextool.fsm;

import dextool.plugin.mutate.backend.database : Database, MutantTimeoutCtx, MutationStatusId;
import dextool.plugin.mutate.backend.type : Mutation;

@safe:

/// Reset the state of the timeout algorithm to its inital state.
void resetTimeoutContext(ref Database db) @trusted {
    db.putMutantTimeoutCtx(MutantTimeoutCtx.init);
}

/// Calculate the timeout to use based on the context.
std_.datetime.Duration calculateTimeout(const long iter, std_.datetime.Duration base) pure nothrow @nogc {
    import core.time : dur;
    import std.math : sqrt;

    static immutable double constant_factor = 1.5;
    static immutable double scale_factor = 2.0;
    const double n = iter;

    const double scale = constant_factor + sqrt(n) * scale_factor;
    return (1L + (cast(long)(base.total!"msecs" * scale))).dur!"msecs";
}

/** Update the status of a mutant.
 *
 * If the mutant is `timeout` then it will be added to the worklist if the
 * mutation testing is in the initial phase.
 *
 * If it has progressed beyond the init phase then it depends on if the local
 * iteration variable of *this* instance of dextool matches the one in the
 * database. This ensures that all instances that work on the same database is
 * in-sync with each other.
 *
 * Params:
 *  db = database to use
 *  id = ?
 *  st = ?
 *  usedIter = the `iter` value that was used to test the mutant
 */
void updateMutantStatus(ref Database db, const MutationStatusId id,
        const Mutation.Status st, const long usedIter) @trusted {
    import std.typecons : Yes;

    const ctx = db.getMutantTimeoutCtx;

    final switch (ctx.state) with (MutantTimeoutCtx.State) {
    case init_:
        if (st == Mutation.Status.timeout)
            db.putMutantInTimeoutWorklist(id);
        db.updateMutationStatus(id, st, Yes.updateTs);
        break;
    case running:
        if (usedIter == ctx.iter) {
            db.updateMutationStatus(id, st, Yes.updateTs);
        }
        break;
    case done:
        break;
    }
}

/** FSM for handling mutants during the test phase.
 */
struct TimeoutFsm {
@safe:

    static struct Init {
    }

    static struct ResetWorkList {
    }

    static struct UpdateCtx {
    }

    static struct Running {
    }

    static struct Purge {
        // worklist items and if they have changed or not
        enum Event {
            changed,
            same
        }

        Event ev;
    }

    static struct Done {
    }

    static struct ClearWorkList {
    }

    static struct Stop {
    }

    /// Data used by all states.
    static struct Global {
        MutantTimeoutCtx ctx;
        Mutation.Kind[] kinds;
        NullableRef!Database db;
    }

    static struct Output {
        /// The current iteration through the timeout algorithm.
        long iter;
        /// When the testing of all timeouts are done, e.g. the state is "done".
        bool done;
    }

    /// Output that may be used.
    Output output;

    private {
        Fsm!(Init, ResetWorkList, UpdateCtx, Running, Purge, Done, ClearWorkList, Stop) fsm;
        Global global;
    }

    this(const Mutation.Kind[] kinds) nothrow {
        global.kinds = kinds.dup;
    }

    void execute(ref Database db) @trusted {
        global.db = nullableRef(&db);

        auto t = db.transaction;
        global.ctx = db.getMutantTimeoutCtx;

        // force the local state to match the starting point in the ctx
        // (database).
        final switch (global.ctx.state) with (MutantTimeoutCtx) {
        case State.init_:
            fsm.state = fsm(Init.init);
            break;
        case State.running:
            fsm.state = fsm(Running.init);
            break;
        case State.done:
            fsm.state = fsm(Done.init);
            break;
        }

        // act on the inital state
        try {
            fsm.act!this;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }

        while (!fsm.isState!Stop) {
            try {
                step(db);
            } catch (Exception e) {
                logger.warning(e.msg).collectException;
            }
        }

        db.putMutantTimeoutCtx(global.ctx);
        t.commit;

        output.iter = global.ctx.iter;
    }

    private void step(ref Database db) @safe {
        bool noUnknown() {
            return db.unknownSrcMutants(global.kinds, null).count == 0;
        }

        fsm.next!((Init a) {
            if (noUnknown)
                return fsm(ResetWorkList.init);
            return fsm(Stop.init);
        }, (ResetWorkList a) => fsm(UpdateCtx.init), (UpdateCtx a) => fsm(Running.init), (Running a) {
            if (noUnknown)
                return fsm(Purge.init);
            return fsm(Stop.init);
        }, (Purge a) {
            final switch (a.ev) with (Purge.Event) {
            case changed:
                return fsm(ResetWorkList.init);
            case same:
                return fsm(ClearWorkList.init);
            }
        }, (ClearWorkList a) => fsm(Done.init), (Done a) {
            // happens if an operation is performed that changes the status of
            // already tested mutants to unknown.
            if (noUnknown)
                return fsm(Stop.init);
            return fsm(Init.init);
        }, (Stop a) => fsm(a),);

        fsm.act!this;
    }

    void opCall(Init) {
        global.ctx = MutantTimeoutCtx.init;
        output.done = false;
    }

    void opCall(ResetWorkList) {
        global.db.resetMutantTimeoutWorklist;
    }

    void opCall(UpdateCtx) {
        global.ctx.iter += 1;
        global.ctx.worklistCount = global.db.countMutantTimeoutWorklist;
    }

    void opCall(Running) {
        global.ctx.state = MutantTimeoutCtx.State.running;
        output.done = false;
    }

    void opCall(ref Purge data) {
        global.db.reduceMutantTimeoutWorklist;

        if (global.db.countMutantTimeoutWorklist == global.ctx.worklistCount)
            data.ev = Purge.Event.same;
        else
            data.ev = Purge.Event.changed;
    }

    void opCall(Done) {
        global.ctx.state = MutantTimeoutCtx.State.done;
        output.done = true;
    }

    void opCall(ClearWorkList) {
        global.db.clearMutantTimeoutWorklist;
    }

    void opCall(Stop) {
    }
}
