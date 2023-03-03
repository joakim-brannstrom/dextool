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

import std.algorithm : joiner, clamp, min, max, filter;
import std.random : uniform01, MinstdRand0, unpredictableSeed;
import std.range : only;

import dextool.plugin.mutate.backend.type : Mutation;

@safe:

enum SchemaStatus {
    /// no status exist
    none,
    /// the schema compiled and the test suite executed OK
    ok,
    /// either it failed to compile or the test suite failed
    broken
}

struct SchemaQ {
    import std.traits : EnumMembers;
    import my.hash;
    import my.path : Path;

    static immutable MinState = 0;
    static immutable MaxState = 1000;
    static immutable LearnRate = 0.01;

    alias StatusData = Mutation.Kind[]delegate(SchemaStatus);

    MinstdRand0 rnd0;
    int[Mutation.Kind][Checksum64] state;
    Checksum64[Path] pathCache;

    static auto make() {
        return SchemaQ(MinstdRand0(unpredictableSeed));
    }

    this(MinstdRand0 rnd) {
        this.rnd0 = rnd;
    }

    this(typeof(state) st) {
        rnd0 = MinstdRand0(unpredictableSeed);
        state = st;
    }

    /// Deep copy.
    SchemaQ dup() {
        typeof(state) st;
        foreach (a; state.byKeyValue) {
            int[Mutation.Kind] v;
            foreach (b; a.value.byKeyValue) {
                v[b.key] = b.value;
            }
            st[a.key] = v;
        }
        return SchemaQ(st);
    }

    /// Add a state for the `p` if it doesn't exist.
    void addIfNew(const Path p) {
        if (checksum(p) !in state) {
            state[checksum(p)] = (int[Mutation.Kind]).init;
        }
    }

    /// Update the state for all mutants.
    void update(const Path path, scope StatusData data) {
        import std.math : round;

        addIfNew(path);
        const ch = checksum(path);

        double[Mutation.Kind] change;

        // punish
        foreach (k; data(SchemaStatus.broken))
            change.update(k, () => (1.0 - LearnRate), (ref double x) {
                x -= LearnRate;
            });
        // reward
        foreach (k; data(SchemaStatus.ok))
            change.update(k, () => (1.0 + LearnRate), (ref double x) {
                x += LearnRate;
            });

        // apply change
        foreach (v; change.byKeyValue.filter!(a => a.value != 1.0)) {
            state[ch].update(v.key, () => cast(int) round(MaxState * v.value), (ref int x) {
                if (v.value > 1.0)
                    x = max(x + 1, cast(int) round(x * v.value));
                else
                    x = min(x - 1, cast(int) round(x * v.value));
            });
        }

        // fix probability to be max P(1)
        foreach (k; change.byKey) {
            state[ch].update(k, () => MaxState, (ref int x) {
                x = clamp(x, MinState, MaxState);
            });
        }
    }

    /** To allow those with zero probability to self heal give them a random +1 now and then.
     */
    void scatterTick() nothrow {
        foreach (p; state.byKeyValue) {
            foreach (k; p.value.byKeyValue.filter!(a => a.value == 0 && uniform01(rnd0) < 0.05)) {
                state[p.key][k.key] = 1;
            }
        }
    }

    /** Roll the dice to see if the mutant should be used.
     *
     * Params:
     *  p = path the mutant is located at.
     *  k = kind of mutant
     *  threshold = the mutants probability must be above the threshold
     *  otherwise it will automatically fail.
     *
     * Return: true if the roll is positive, use the mutant.
     */
    bool use(const Path p, const Mutation.Kind k, const double threshold) {
        const s = getState(p, k) / cast(double) MaxState;
        return s >= threshold && uniform01(rnd0) < s;
    }

    /// Returns: true if the probability of success is zero.
    bool isZero(const Path p, const Mutation.Kind k) {
        return getState(p, k) == 0;
    }

    private Checksum64 checksum(const Path p) {
        return pathCache.require(p, makeChecksum64(cast(const(ubyte)[]) p.toString));
    }

    private int getState(const Path p, const Mutation.Kind k) {
        if (auto st = checksum(p) in state)
            return (*st).require(k, MaxState);
        return MaxState;
    }
}

struct Feature {
    import my.hash;

    // The path is extremly important because it allows the tool to clear out old data.
    Checksum64 path;

    Mutation.Kind kind;

    Checksum64[] context;

    size_t toHash() @safe pure nothrow const @nogc {
        auto rval = (cast(size_t) kind).hashOf();
        rval = path.c0.hashOf(rval);
        foreach (a; context)
            rval = a.c0.hashOf(rval);
        return rval;
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
    assert(q.state[ch][Mutation.Kind.rorLE] == 990);
    assert(q.state[ch][Mutation.Kind.rorLT] == SchemaQ.MaxState);

    Mutation.Kind[] r2(SchemaStatus s) {
        if (s == SchemaStatus.broken)
            return [Mutation.Kind.rorLE, Mutation.Kind.rorLT];
        if (s == SchemaStatus.ok)
            return [Mutation.Kind.rorLT];
        return null;
    }

    q.update(foo, &r2);
    assert(q.state[ch][Mutation.Kind.rorLE] == 980);
    // in the last run it was one broken and one OK thus the change where 1.0.
    assert(q.state[ch][Mutation.Kind.rorLT] == SchemaQ.MaxState);
}

struct SchemaSizeQ {
    static immutable LearnRate = 0.01;
    static immutable Threshold = 0.9;

    /// min size of a schema.
    long minSize;
    /// max size of a schema.
    long maxSize;
    /// current size of that are used to generate scheman.
    private long currentSize_;
    /// total number of mutants that are to be tested when schemas are generated.
    long testMutantsSize;

    static auto make(const long minSize, const long maxSize) {
        return SchemaSizeQ(minSize, maxSize, maxSize);
    }

    void updateSize(const double sz) @safe pure nothrow @nogc {
        currentSize_ = clamp(cast(long) sz, minSize, maxSize);
    }

    long currentSize() @safe pure nothrow const @nogc {
        return currentSize_;
    }

    /**
     * Params:
     *  schemaMutants = mutants in the schema
     */
    void update(const SchemaStatus status, const long schemaMutants) {
        double newValue = currentSize_;

        double adjust = 1.0;
        // ensure there is at least some change.
        long fixed;

        final switch (status) {
        case SchemaStatus.none:
            break;
        case SchemaStatus.ok:
            // only try to increase the size if the schema where close to max
            if (maxSize > 0 && schemaMutants > currentSize_ * Threshold) {
                adjust += LearnRate * (cast(double) schemaMutants / cast(double) maxSize);
                fixed++;
            }
            break;
        case SchemaStatus.broken:
            if (maxSize > 0 && schemaMutants > currentSize_ * Threshold) {
                adjust -= LearnRate * (cast(double) schemaMutants / cast(double) maxSize);
                fixed--;
            }
            break;
        }

        updateSize(newValue * adjust + fixed);
    }

    /// No schema with `currentSize_` where generated.
    void noCurrentSize() {
        if (maxSize > 0 && testMutantsSize > currentSize_ * Threshold)
            updateSize(currentSize_ - currentSize_ * LearnRate);
    }

    string toString() @safe pure const {
        import std.format : format;

        return format!"SchemaSizeQ(min:%s, max:%s, current:%s, testMutantsSize:%s)"(minSize,
                maxSize, currentSize_, testMutantsSize);
    }
}
