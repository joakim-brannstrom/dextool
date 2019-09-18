/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains utilities to reduce the boilerplate when implementing a
FSM.

# Callback Builder
Useful to generate the callbacks that control the actions to perform in an FSM
or the state transitions.
*/
module dextool.fsm;

import logger = std.experimental.logger;

version (unittest) {
    import unit_threaded.assertions;
}

/** A state machine derived from the types it is based on.
 *
 * Each state have its unique data that it works on.
 *
 * The state transitions are calculated by `next` and the actions are performed
 * by `act`.
 */
struct Fsm(StateTT...) {
    static import sumtype;

    alias StateT = sumtype.SumType!StateTT;

    /// The states and state specific data.
    StateT state;

    /// Helper function to convert the return type to `StateT`.
    static StateT opCall(T)(auto ref T a) {
        return StateT(a);
    }

    /// Returns: true if the fsm is in the specified state.
    bool isState(Ts...)() {
        import std.meta : AliasSeq;

        template Fns(Ts...) {
            static if (Ts.length == 0) {
                alias Fns = AliasSeq!();
            } else static if (Ts.length == 1) {
                alias Fns = AliasSeq!((Ts[0] a) => true);
            } else {
                alias Fns = AliasSeq!(Fns!(Ts[0 .. $ / 2]), Fns!(Ts[$ / 2 .. $]));
            }
        }

        try {
            return sumtype.tryMatch!(Fns!Ts)(state);
        } catch (Exception e) {
        }
        return false;
    }
}

/// Transition to the next state.
template next(handlers...) {
    void next(Self)(auto ref Self self) if (is(Self : Fsm!StateT, StateT...)) {
        static import sumtype;

        auto nextSt = sumtype.match!handlers(self.state);
        logger.tracef("state: %s -> %s", self.state.toString, nextSt.toString);
        self.state = nextSt;
    }
}

/// Act on the current state. Use `(ref S)` to modify the states data.
template act(handlers...) {
    void act(Self)(auto ref Self self) if (is(Self : Fsm!StateT, StateT...)) {
        static import sumtype;

        logger.trace("act: ", self.state.toString);
        sumtype.match!handlers(self.state);
    }
}

@("shall transition the fsm from A to B|C")
unittest {
    struct Global {
        int x;
    }

    struct A {
    }

    struct B {
        int x;
    }

    struct C {
        bool x;
    }

    Global global;
    Fsm!(A, B, C) fsm;

    while (!fsm.isState!(B, C)) {
        fsm.next!((A a) { global.x++; return fsm(B(0)); }, (B a) {
            if (a.x > 3)
                return fsm(C(true));
            return fsm(a);
        }, (C a) { return fsm(a); });

        fsm.act!((A a) {}, (ref B a) { a.x++; }, (C a) {});
    }

    global.x.shouldEqual(1);
}
