/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Q-learning algorithm for training the schema generator.

Each mutation subtype has a state in range [0,100]. It determins the
probability that a mutant of that kind is part of the intermediate schema
generation.

The state is updated with feedback from if the schema successfully compiled and
executed the test suite OK.
*/
module dextool.plugin.mutate.backend.analyze.schema_ml;

import std.algorithm : min, max;

import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.backend.database.type : SchemaStatus;

@safe:

immutable MinState = 0;
immutable MaxState = 100;
immutable LearnRate = 0.1;

struct SchemaQ {
    import std.random : uniform01, MinstdRand0, unpredictableSeed;

    alias StatusData = Mutation.Kind[]delegate(SchemaStatus);

    MinstdRand0 rnd0;
    int[Mutation.Kind] state;

    static auto make() {
        return SchemaQ(MinstdRand0(unpredictableSeed));
    }

    /// Update the state for all mutants.
    void update(StatusData data) {
        import std.algorithm : joiner;
        import std.range : only;
        import std.traits : EnumMembers;

        // punish
        foreach (k; data(SchemaStatus.broken))
            state.update(k, () => cast(int)(MaxState * (1.0 - LearnRate)), (ref int x) {
                x = cast(int) min(x - 1, cast(int)(x * (1.0 - LearnRate)));
            });
        // reward
        foreach (k; only(data(SchemaStatus.ok), data(SchemaStatus.allKilled)).joiner)
            state.update(k, () => cast(int) MaxState, (ref int x) {
                x = max(x + 1, cast(int)(x * (1.0 + LearnRate)));
            });

        // clamp values
        foreach (k; [EnumMembers!(Mutation.Kind)])
            state.update(k, () => cast(int) MaxState, (ref int x) {
                x = cast(int) min(MaxState, max(0, x));
            });
    }

    /// Return: random value using the mutation subtype probability.
    bool use(Mutation.Kind k) {
        auto p = state.require(k, MaxState) / 100.0;
        return uniform01 < p;
    }
}

@("shall update the table")
unittest {
    import std.random : MinstdRand0;

    SchemaQ q;
    q.rnd0 = MinstdRand0(42);

    Mutation.Kind[] r1(SchemaStatus s) {
        if (s == SchemaStatus.broken)
            return [Mutation.Kind.rorLE];
        if (s == SchemaStatus.ok)
            return [Mutation.Kind.rorLT];
        return null;
    }

    q.update(&r1);
    assert(q.state[Mutation.Kind.rorLE] == 90);
    assert(q.state[Mutation.Kind.rorLT] == 100);

    Mutation.Kind[] r2(SchemaStatus s) {
        if (s == SchemaStatus.broken)
            return [Mutation.Kind.rorLE, Mutation.Kind.rorLT];
        if (s == SchemaStatus.allKilled)
            return [Mutation.Kind.rorLT];
        return null;
    }

    q.update(&r2);
    assert(q.state[Mutation.Kind.rorLE] == 81);
    assert(q.state[Mutation.Kind.rorLT] == 99);
}
