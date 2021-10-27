/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Utility for manually profiling of parts of a program.
*/
module my.profile;

import core.sync.mutex : Mutex;
import std.datetime : Duration;

/// Execution profile result gathered from analysers.
private shared ProfileResults gProfile;
private shared Mutex gProfileMtx;

/// Returns: the profiling results gathered for this module.
ProfileResults getProfileResult() @trusted {
    gProfileMtx.lock_nothrow;
    scope (exit)
        gProfileMtx.unlock_nothrow();
    auto g = cast() gProfile;
    return new ProfileResults(g.results.dup);
}

void globalSetProfile(string name, Duration time) @trusted {
    gProfileMtx.lock_nothrow;
    scope (exit)
        gProfileMtx.unlock_nothrow();
    auto g = cast() gProfile;
    g.set(name, time);
}

void globalAddProfile(string name, Duration time) @trusted {
    gProfileMtx.lock_nothrow;
    scope (exit)
        gProfileMtx.unlock_nothrow();
    auto g = cast() gProfile;
    g.add(name, time);
}

shared static this() {
    gProfileMtx = new shared Mutex();
    gProfile = cast(shared) new ProfileResults;
}

@safe:

/** Wall time profile of a task.
 *
 * If no results collector is specified the result is stored in the global
 * collector.
 */
struct Profile {
    import std.datetime.stopwatch : StopWatch;

    enum Op {
        add,
        set
    }

    string name;
    StopWatch sw;
    ProfileResults saveTo;
    Op op;

    this(T)(T name, Op op, ProfileResults saveTo = null) @safe nothrow {
        static if (is(T == string)) {
            this.name = name;
        } else {
            try {
                this.name = name.to!string;
            } catch (Exception e) {
                this.name = T.stringof;
            }
        }
        this.saveTo = saveTo;
        this.op = op;
        sw.start;
    }

    ~this() @safe nothrow {
        // uninitialized
        if (name.length == 0)
            return;

        try {
            sw.stop;
            if (saveTo is null) {
                final switch (op) {
                case Op.set:
                    globalSetProfile(name, sw.peek);
                    break;
                case Op.add:
                    globalAddProfile(name, sw.peek);
                    break;
                }
            } else {
                saveTo.add(name, sw.peek);
            }
        } catch (Exception e) {
        }
    }
}

Profile profileSet(string name, ProfileResults saveTo = null) {
    return Profile(name, Profile.Op.set, saveTo);
}

Profile profileAdd(string name, ProfileResults saveTo = null) {
    return Profile(name, Profile.Op.add, saveTo);
}

/** Collect profiling results.
 */
class ProfileResults {
    import std.algorithm : sum, map, sort;
    import std.array : array, appender;

    struct Result {
        string name;
        Duration time;
        double ratio;
    }

    /// The profiling for the same name is accumulated.
    Duration[string] results;

    this() {
    }

    this(typeof(results) results) {
        this.results = results;
    }

    /// Add `time` to `name`.
    void add(string name, Duration time) {
        results.update(name, () => time, (ref Duration a) { a += time; });
    }

    /// Set `name` to `time`.
    void set(string name, Duration time) {
        results.update(name, () => time, (ref Duration a) { a = time; });
    }

    /// Returns: the total wall time.
    Duration totalTime() const {
        return results.byValue.sum(Duration.zero);
    }

    /// Returns;
    Result[] toRows() const {
        auto app = appender!(Result[])();
        const double total = totalTime.total!"nsecs";

        foreach (a; results.byKeyValue.array.sort!((a, b) => a.value < b.value)) {
            Result row;
            row.name = a.key;
            row.time = a.value;
            row.ratio = cast(double) a.value.total!"nsecs" / total;
            app.put(row);
        }

        return app.data;
    }

    /**
     *
     * This is an example from clang-tidy for how it could be reported to the user.
     * For now it is *just* reported as it is running.
     *
     * ===-------------------------------------------------------------------------===
     *                           clang-tidy checks profiling
     * ===-------------------------------------------------------------------------===
     *   Total Execution Time: 0.0021 seconds (0.0021 wall clock)
     *
     *    ---User Time---   --System Time--   --User+System--   ---Wall Time---  --- Name ---
     *    0.0000 (  0.1%)   0.0000 (  0.0%)   0.0000 (  0.0%)   0.0000 (  0.1%)  readability-misplaced-array-index
     *    0.0000 (  0.2%)   0.0000 (  0.0%)   0.0000 (  0.1%)   0.0000 (  0.1%)  abseil-duration-division
     *    0.0012 (100.0%)   0.0009 (100.0%)   0.0021 (100.0%)   0.0021 (100.0%)  Total
     */
    override string toString() const {
        import std.algorithm : maxElement;
        import std.format : format, formattedWrite;
        import std.math : log10;

        const sec = 1000000000.0;
        // 16 is the number of letters after the dot in "0.0000 (100.1%)" + 1 empty whitespace.
        const wallMaxLen = cast(int) results.byValue.map!(a => a.total!"seconds")
            .maxElement(1).log10 + 15;

        auto app = appender!string;
        formattedWrite(app,
                "===-------------------------------------------------------------------------===\n");
        formattedWrite(app, "                                 profiling\n");
        formattedWrite(app,
                "===-------------------------------------------------------------------------===\n");
        formattedWrite(app, "Total execution time: %.4f seconds\n\n",
                cast(double) totalTime.total!"nsecs" / sec);
        formattedWrite(app, "---Wall Time--- ---Name---\n");

        void print(string name, Duration time, double ratio) {
            auto wt = format!"%.4f (%.1f%%)"(cast(double) time.total!"nsecs" / sec, ratio * 100.0);
            formattedWrite(app, "%-*s %s\n", wallMaxLen, wt, name);
        }

        foreach (r; toRows) {
            print(r.name, r.time, r.ratio);
        }

        return app.data;
    }
}

@("shall accumulate profiling results")
unittest {
    import std.conv : to;
    import std.stdio : writeln;

    auto pc = new ProfileResults;

    foreach (_; 0 .. 10)
        auto p = profileSet("a", pc);
    assert(pc.toRows.length == 1);

    foreach (i; 0 .. 10)
        auto p = profileAdd("a" ~ i.to!string, pc);
    assert(pc.toRows.length == 11);

    writeln(pc);
}
