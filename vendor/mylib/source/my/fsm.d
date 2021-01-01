/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module my.fsm;

import std.format : format;

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

    /// Log messages of the last state transition (next).
    /// Only updated in debug build.
    string logNext;

    /// Helper function to convert the return type to `StateT`.
    static StateT opCall(T)(auto ref T a) {
        return StateT(a);
    }
}

/// Transition to the next state.
template next(handlers...) {
    void next(Self)(auto ref Self self) if (is(Self : Fsm!StateT, StateT...)) {
        import std.meta : staticMap;
        import std.traits : Parameters, ReturnType;
        static import sumtype;

        template CoerceReturn(alias Matcher) {
            alias P = Parameters!Matcher;
            static if (is(ReturnType!Matcher == Self.StateT)) {
                alias CoerceReturn = Matcher;
            } else {
                static Self.StateT CoerceReturn(P[0] a) {
                    return Self.StateT(Matcher(a));
                }
            }
        }

        alias Handlers = staticMap!(CoerceReturn, handlers);

        auto nextSt = sumtype.match!Handlers(self.state);
        debug self.logNext = format!"%s -> %s"(self.state, nextSt);

        self.state = nextSt;
    }
}

/// Act on the current state. Use `(ref S)` to modify the states data.
template act(handlers...) {
    void act(Self)(auto ref Self self) if (is(Self : Fsm!StateT, StateT...)) {
        static import sumtype;

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
    bool running = true;

    while (running) {
        fsm.next!((A a) { global.x++; return fsm(B(0)); }, (B a) {
            running = false;
            if (a.x > 3)
                return fsm(C(true));
            return fsm(a);
        }, (C a) { running = false; return a; });

        fsm.act!((A a) {}, (ref B a) { a.x++; }, (C a) {});
    }

    assert(global.x == 1);
}

@("shall use a struct to provide the state callbacks")
unittest {
    static struct A {
    }

    static struct B {
    }

    static struct Foo {
        Fsm!(A, B) fsm;
        bool running = true;

        void opCall(A a) {
        }

        void opCall(B b) {
            running = false;
        }
    }

    Foo foo;
    while (foo.running) {
        foo.fsm.next!((A a) => B.init, (B a) => a);
        foo.fsm.act!foo;
    }
}

/** Hold a mapping between a Type and data.
 *
 * The get function is used to get the corresponding data.
 *
 * This is useful when e.g. combined with a state machine to retrieve the state
 * local data if a state is represented as a type.
 *
 * Params:
 *  RawDataT = type holding the data, retrieved via opIndex
 *  Ts = the types mapping to RawDataT by their position
 */
struct TypeDataMap(RawDataT, Ts...)
        if (is(RawDataT : DataT!Args, alias DataT, Args...)) {
    alias SrcT = Ts;
    RawDataT data;

    this(RawDataT a) {
        this.data = a;
    }

    void opAssign(RawDataT a) {
        this.data = a;
    }

    static if (is(RawDataT : DataT!Args, alias DataT, Args...))
        static assert(Ts.length == Args.length,
                "Mismatch between Tuple and TypeMap template arguments");
}

auto ref get(T, TMap)(auto ref TMap tmap)
        if (is(TMap : TypeDataMap!(W, SrcT), W, SrcT...)) {
    template Index(size_t Idx, T, Ts...) {
        static if (Ts.length == 0) {
            static assert(0, "Type " ~ T.stringof ~ " not found in the TypeMap");
        } else static if (is(T == Ts[0])) {
            enum Index = Idx;
        } else {
            enum Index = Index!(Idx + 1, T, Ts[1 .. $]);
        }
    }

    return tmap.data[Index!(0, T, TMap.SrcT)];
}

@("shall retrieve the data for the type")
unittest {
    import std.typecons : Tuple;

    TypeDataMap!(Tuple!(int, bool), bool, int) a;
    static assert(is(typeof(a.get!bool) == int), "wrong type");
    a.data[1] = true;
    assert(a.get!int == true);
}
