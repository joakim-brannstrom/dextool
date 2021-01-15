/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.utility;

import core.time : Duration;
import logger = std.experimental.logger;
import std.algorithm : filter, map, splitter, sum, sort;
import std.array : appender, array;
import std.conv : to;
import std.typecons : Flag, No, Tuple;
import core.sync.mutex : Mutex;

import my.from_;

import my.hash : BuildChecksum128, toChecksum128;
import dextool.type : Path, AbsolutePath;

public import my.hash : toBytes;

public import dextool.plugin.mutate.backend.type;
public import dextool.plugin.mutate.backend.mutation_type;
public import dextool.clang_extensions : OpKind;
public import dextool.plugin.mutate.backend.interface_ : Blob;

/// Execution profile result gathered from analysers.
private shared ProfileResults gProfile;
private shared Mutex gProfileMtx;

alias BuildChecksum = BuildChecksum128;
alias toChecksum = toChecksum128;

/// Returns: the profiling results gathered for this module.
ProfileResults getProfileResult() @trusted {
    gProfileMtx.lock_nothrow;
    scope (exit)
        gProfileMtx.unlock_nothrow();
    auto g = cast() gProfile;
    return new ProfileResults(g.results.dup);
}

void putProfile(string name, Duration time) @trusted {
    gProfileMtx.lock_nothrow;
    scope (exit)
        gProfileMtx.unlock_nothrow();
    auto g = cast() gProfile;
    g.put(name, time);
}

shared static this() {
    gProfileMtx = new shared Mutex();
    gProfile = cast(shared) new ProfileResults;
}

@safe:

Checksum checksum(const(ubyte)[] a) {
    import my.hash : makeMurmur3;

    return makeMurmur3(a);
}

Checksum checksum(AbsolutePath p) @trusted {
    import std.mmfile : MmFile;

    try {
        scope content = new MmFile(p.toString);
        return checksum(cast(const(ubyte)[]) content[]);
    } catch (Exception e) {
    }

    return Checksum.init;
}

/// Package the values to a checksum.
Checksum checksum(T)(const(T[2]) a) if (T.sizeof == 8) {
    return Checksum(cast(ulong) a[0], cast(ulong) a[1]);
}

/// Package the values to a checksum.
Checksum checksum(T)(const T a, const T b) if (T.sizeof == 8) {
    return Checksum(cast(ulong) a, cast(ulong) b);
}

/// Sleep for a random time that is min_ + rnd(0, span msecs)
void rndSleep(Duration min_, int span) nothrow @trusted {
    import core.thread : Thread;
    import core.time : dur;
    import std.random : uniform;

    auto t_span = () {
        try {
            return uniform(0, span).dur!"msecs";
        } catch (Exception e) {
        }
        return span.dur!"msecs";
    }();

    Thread.sleep(min_ + t_span);
}

/** Returns: the file content as an array of tokens.
 *
 * This is a bit slow, I think. Optimize by reducing the created strings.
 * trusted: none of the unsafe accessed data escape this function.
 *
 * Params:
 *  splitMultiLineTokens = a token, mostly comment tokens, can be over multiple
 *      lines. If true then this split it into multiple tokens where a token is at
 *      most one per line.
 */
auto tokenize(Flag!"splitMultiLineTokens" splitTokens = No.splitMultiLineTokens)(
        ref from.cpptooling.analyzer.clang.context.ClangContext ctx, Path file) @trusted {
    import std.range : enumerate;

    auto tu = ctx.makeTranslationUnit(file);
    auto toks = appender!(Token[])();
    foreach (ref t; tu.cursor.tokens) {
        const ext = t.extent;
        const start = ext.start;
        const end = ext.end;
        const spell = t.spelling;

        static if (splitTokens) {
            // TODO: this do not correctly count the utf-8 graphems but rather
            // the code points because `.length` is used.

            auto offset = Offset(start.offset, start.offset);
            auto startLoc = SourceLoc(start.line, start.column);
            auto endLoc = startLoc;
            foreach (ts; spell.splitter('\n').enumerate) {
                offset = Offset(offset.end, cast(uint)(offset.end + ts.length));

                if (ts.index == 0) {
                    endLoc = SourceLoc(start.line, cast(uint)(start.column + ts.value.length));
                } else {
                    startLoc = SourceLoc(startLoc.line + 1, 1);
                    endLoc = SourceLoc(startLoc.line, cast(uint) ts.value.length);
                }

                toks.put(Token(t.kind, offset, startLoc, endLoc, ts.value));
            }
        } else {
            auto offset = Offset(start.offset, end.offset);
            auto startLoc = SourceLoc(start.line, start.column);
            auto endLoc = SourceLoc(end.line, end.column);
            toks.put(Token(t.kind, offset, startLoc, endLoc, spell));
        }
    }

    return toks.data;
}

struct TokenRange {
    private {
        Token[] tokens;
    }

    Token front() @safe pure nothrow {
        assert(!empty, "Can't get front of an empty range");
        return tokens[0];
    }

    void popFront() @safe pure nothrow {
        assert(!empty, "Can't pop front of an empty range");
        tokens = tokens[1 .. $];
    }

    bool empty() @safe pure nothrow const @nogc {
        return tokens.length == 0;
    }
}

/** Collect profiling results
 *
 */
class ProfileResults {
    alias Result = Tuple!(string, "name", Duration, "time", double, "ratio");
    /// The profiling for the same name is accumulated.
    Duration[string] results;

    this() {
    }

    this(typeof(results) results) {
        this.results = results;
    }

    void put(string name, Duration time) {
        if (auto v = name in results) {
            (*v) += time;
        } else {
            results[name] = time;
        }
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
        formattedWrite(app, "                         dextool profiling\n");
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

/** Wall time profile of a task.
 *
 * If no results collector is specified the result is stored in the global
 * collector.
 */
struct Profile {
    import std.datetime.stopwatch : StopWatch;

    string name;
    StopWatch sw;
    ProfileResults saveTo;

    this(T)(T name, ProfileResults saveTo = null) @safe nothrow {
        try {
            this.name = name.to!string;
        } catch (Exception e) {
            this.name = T.stringof;
        }
        this.saveTo = saveTo;
        sw.start;
    }

    ~this() @safe nothrow {
        try {
            sw.stop;
            if (saveTo is null) {
                putProfile(name, sw.peek);
            } else {
                saveTo.put(name, sw.peek);
            }
        } catch (Exception e) {
        }
    }
}
