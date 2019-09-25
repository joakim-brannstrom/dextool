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
import std.algorithm : filter;
import std.typecons : Flag, No;

import dextool.type : Path, AbsolutePath;
import dextool.from;

public import dextool.plugin.mutate.backend.type;
public import dextool.plugin.mutate.backend.mutation_type;
public import dextool.clang_extensions : OpKind;
public import dextool.plugin.mutate.backend.interface_ : Blob;

@safe:

Path trustedRelativePath(string p, AbsolutePath root) @trusted {
    import std.path : relativePath;

    return relativePath(p, root).Path;
}

/**
 * trusted: void[] is perfectly representable as ubyte[] accoding to the specification.
 */
Checksum checksum(const(ubyte)[] a) {
    import dextool.hash : makeMurmur3;

    return makeMurmur3(a);
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
        ref from!"cpptooling.analyzer.clang.context".ClangContext ctx, Path file) @trusted {
    import std.algorithm : splitter;
    import std.array : appender;
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
