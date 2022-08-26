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

import miniorm : spinSql;
import my.from_;
import my.fsm;

import dextool.plugin.mutate.backend.database : Database, MutantTimeoutCtx, MutationStatusId;
import dextool.plugin.mutate.backend.type : Mutation, ExitStatus;

@safe:

/// How the timeout is configured and what it is.
struct TimeoutConfig {
    import std.datetime : Duration;

    double timeoutScaleFactor = 2.0;

    private {
        bool userConfigured_;
        Duration baseTimeout;
        long iteration;
    }

    bool isUserConfig() @safe pure nothrow const @nogc {
        return userConfigured_;
    }

    /// Force the value to be this
    void userConfigured(Duration t) @safe pure nothrow @nogc {
        userConfigured_ = true;
        baseTimeout = t;
    }

    /// Only set the timeout if it isnt set by the user.
    void set(Duration t) @safe pure nothrow @nogc {
        if (!userConfigured_)
            baseTimeout = t;
    }

    void updateIteration(long x) @safe pure nothrow @nogc {
        iteration = x;
    }

    long iter() @safe pure nothrow const @nogc {
        return iteration;
    }

    Duration value() @safe pure nothrow const @nogc {
        import std.algorithm : max;
        import std.datetime : dur;

        // Assuming that a timeout <1s is too strict because of OS jitter and load.
        // It would lead to "false" timeout status of mutants.
        return max(1.dur!"seconds", calculateTimeout(iteration, baseTimeout, timeoutScaleFactor));
    }

    Duration base() @safe pure nothrow const @nogc {
        return baseTimeout;
    }
}

/// Reset the state of the timeout algorithm to its inital state.
void resetTimeoutContext(ref Database db) @trusted {
    db.timeoutApi.put(MutantTimeoutCtx.init);
}

/// Calculate the timeout to use based on the context.
std_.datetime.Duration calculateTimeout(const long iter,
        std_.datetime.Duration base, const double timeoutScaleFactor) pure nothrow @nogc {
    import core.time : dur;
    import std.math : sqrt;

    static immutable double constant_factor = 1.5;
    const double n = iter;

    const double scale = constant_factor + sqrt(n) * timeoutScaleFactor;
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
        const Mutation.Status st, const ExitStatus ecode, const long usedIter) @trusted {
    import std.typecons : Yes;

    // TODO: ugly hack to integrate memory overload with timeout. Refactor in
    // the future. It is just, the most convenient place to do it at the
    // moment.

    assert(MaxTimeoutIterations - 1 > 0,
            "MaxTimeoutIterations configured too low for memOverload to use it");

    if (st == Mutation.Status.timeout && usedIter == 0)
        db.timeoutApi.put(id, usedIter);
    else
        db.timeoutApi.update(id, usedIter);

    if (st == Mutation.Status.memOverload && usedIter < MaxTimeoutIterations - 1) {
        // the overloaded need to be re-tested a couple of times.
        db.memOverloadApi.put(id);
    }

    db.mutantApi.update(id, st, ecode, Yes.updateTs);
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
        Database* db;
        bool stop;
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
        try {
            if (logger.globalLogLevel == logger.LogLevel.trace)
                fsm.logger = (string s) { logger.trace(s); };
        } catch (Exception e) {
            logger.trace(e.msg).collectException;
        }
    }

    void execute(ref Database db) @trusted {
        execute_(this, &db);
    }

    static void execute_(ref TimeoutFsm self, Database* db) @trusted {
        self.global.db = db;
        // must always run the loop at least once.
        self.global.stop = false;

        auto t = db.transaction;
        self.global.ctx = db.timeoutApi.getMutantTimeoutCtx;

        // force the local state to match the starting point in the ctx
        // (database).
        final switch (self.global.ctx.state) with (MutantTimeoutCtx) {
        case State.init_:
            self.fsm.state = fsm(Init.init);
            break;
        case State.running:
            self.fsm.state = fsm(Running.init);
            break;
        case State.done:
            self.fsm.state = fsm(Done.init);
            break;
        }

        // act on the inital state
        try {
            self.fsm.act!self;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }

        while (!self.global.stop) {
            try {
                step(self, *db);
            } catch (Exception e) {
                logger.warning(e.msg).collectException;
            }
        }

        db.timeoutApi.put(self.global.ctx);
        t.commit;

        self.output.iter = self.global.ctx.iter;
    }

    private static void step(ref TimeoutFsm self, ref Database db) @safe {
        bool noUnknown() {
            return db.mutantApi.unknownSrcMutants(self.global.kinds, null)
                .count == 0 && db.worklistApi.getCount == 0;
        }

        self.fsm.next!((Init a) {
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
                if (self.global.ctx.iter == MaxTimeoutIterations) {
                    return fsm(ClearWorkList.init);
                }
                return fsm(ResetWorkList.init);
            case same:
                return fsm(ClearWorkList.init);
            }
        }, (ClearWorkList a) => fsm(Done.init), (Done a) {
            if (noUnknown)
                return fsm(Stop.init);
            // happens if an operation is performed that changes the status of
            // already tested mutants to unknown.
            return fsm(Running.init);
        }, (Stop a) => fsm(a),);

        self.fsm.act!self;
    }

    void opCall(Init) {
        global.ctx = MutantTimeoutCtx.init;
        output.done = false;
    }

    void opCall(ResetWorkList) {
        global.db.timeoutApi.copyMutantTimeoutWorklist(global.ctx.iter);

        global.db.memOverloadApi.toWorklist;
        global.db.memOverloadApi.clear;
    }

    void opCall(UpdateCtx) {
        global.ctx.iter += 1;
        global.ctx.worklistCount = global.db.timeoutApi.countMutantTimeoutWorklist;
    }

    void opCall(Running) {
        global.ctx.state = MutantTimeoutCtx.State.running;
        output.done = false;
    }

    void opCall(ref Purge data) {
        global.db.timeoutApi.reduceMutantTimeoutWorklist(global.ctx.iter);

        if (global.db.timeoutApi.countMutantTimeoutWorklist == global.ctx.worklistCount) {
            data.ev = Purge.Event.same;
        } else {
            data.ev = Purge.Event.changed;
        }
    }

    void opCall(Done) {
        global.ctx.state = MutantTimeoutCtx.State.done;
        // must reset in case the mutation testing reach the end and is
        // restarted with another mutation operator type than previously
        global.ctx.iter = 0;
        global.ctx.worklistCount = 0;

        output.done = true;
    }

    void opCall(ClearWorkList) {
        global.db.timeoutApi.clearMutantTimeoutWorklist;

        global.db.memOverloadApi.toWorklist;
        global.db.memOverloadApi.clear;
    }

    void opCall(Stop) {
        global.stop = true;
    }
}

// If the mutants has been tested 2 times it should be good enough. Sometimes
// there are so many timeout that it would feel like the tool just end up in an
// infinite loop. Maybe this should be moved so it is user configurable in the
// future.
// The user also have the admin operation stopTimeoutTest to use.
immutable MaxTimeoutIterations = 2;
