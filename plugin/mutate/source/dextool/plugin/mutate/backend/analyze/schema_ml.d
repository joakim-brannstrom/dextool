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

import dextool.plugin.mutate.backend.type : Mutation;
import dextool.plugin.mutate.backend.database.type : SchemaStatus;

@safe:

immutable MinState = 0;
immutable MaxState = 100;
immutable LearnRate = 0.1;

struct SchemaQ {
    import std.algorithm : min, max;
    import std.random : uniform01, MinstdRand0, unpredictableSeed;
    import std.traits : EnumMembers;
    import my.hash;
    import my.path : Path;

    alias StatusData = Mutation.Kind[]delegate(SchemaStatus);

    MinstdRand0 rnd0;
    int[Mutation.Kind][Checksum64] state;
    Checksum64[Path] pathCache;

    static auto make() {
        return SchemaQ(MinstdRand0(unpredictableSeed));
    }

    /// Add a state for the `p` if it doesn't exist.
    void addIfNew(const Path p) {
        if (checksum(p) !in state) {
            state[checksum(p)] = (int[Mutation.Kind]).init;
        }
    }

    /// Update the state for all mutants.
    void update(const Path path, scope StatusData data) {
        import std.algorithm : joiner, clamp;
        import std.range : only;

        addIfNew(path);
        const ch = checksum(path);

        // punish
        foreach (k; data(SchemaStatus.broken))
            state[ch].update(k, () => cast(int)(MaxState * (1.0 - LearnRate)), (ref int x) {
                x = cast(int) min(x - 1, cast(int)(x * (1.0 - LearnRate)));
            });
        // reward
        foreach (k; only(data(SchemaStatus.ok), data(SchemaStatus.allKilled)).joiner)
            state[ch].update(k, () => cast(int) MaxState, (ref int x) {
                x = max(x + 1, cast(int)(x * (1.0 + LearnRate)));
            });

        // fix probability to be max P(1)
        foreach (k; [EnumMembers!(Mutation.Kind)])
            state[ch].update(k, () => cast(int) MaxState, (ref int x) {
                x = clamp(x, MinState, MaxState);
            });
    }

    /// Return: random value using the mutation subtype probability.
    bool use(const Path p, const Mutation.Kind k) {
        const r = uniform01;
        return r < getState(p, k) / cast(double) MaxState;
    }

    private Checksum64 checksum(const Path p) {
        return pathCache.require(p, makeChecksum64(cast(const(ubyte)[]) p.toString));
    }

    private int getState(const Path p, const Mutation.Kind k) {
        if (auto st = checksum(p) in state)
            return (*st)[k];
        return MaxState;
    }
}

@("shall update the table")
unittest {
    import std.random : MinstdRand0;
    import my.path : Path;

    const foo = Path("foo");
    SchemaQ q;
    q.rnd0 = MinstdRand0(42);

    Mutation.Kind[] r1(SchemaStatus s) {
        if (s == SchemaStatus.broken)
            return [Mutation.Kind.rorLE];
        if (s == SchemaStatus.ok)
            return [Mutation.Kind.rorLT];
        return null;
    }

    q.update(foo, &r1);
    const ch = q.pathCache[foo];
    assert(q.state[ch][Mutation.Kind.rorLE] == 90);
    assert(q.state[ch][Mutation.Kind.rorLT] == MaxState);

    Mutation.Kind[] r2(SchemaStatus s) {
        if (s == SchemaStatus.broken)
            return [Mutation.Kind.rorLE, Mutation.Kind.rorLT];
        if (s == SchemaStatus.allKilled)
            return [Mutation.Kind.rorLT];
        return null;
    }

    q.update(foo, &r2);
    assert(q.state[ch][Mutation.Kind.rorLE] == 81);
    assert(q.state[ch][Mutation.Kind.rorLT] == 99);
}
