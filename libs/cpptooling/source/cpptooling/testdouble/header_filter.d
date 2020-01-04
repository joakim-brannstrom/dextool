/**
Copyright: Copyright (c) 2015-2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.testdouble.header_filter;

import std.regex : Regex;
import logger = std.experimental.logger;

enum LocationType {
    Root,
    Leaf
}

enum DummyPayload {
    none
}

/** Includes intended for the test double.
 *
 * Filtered according to the user.
 *
 * State diagram in plantuml:
 * @startuml
 * [*] -> Waiting
 * Waiting: Initialize pool
 *
 * Waiting -> SymbolInclude: Add
 * Waiting --> RootInclude: Add root
 * Waiting --> UserInclude: Add user
 * Waiting --> Finalize: Done
 *
 * UserInclude: Static pool from CLI
 *
 * SymbolInclude: Temp pool of includes
 * SymbolInclude --> SymbolInclude: Add
 * SymbolInclude --> Process: Done
 * SymbolInclude --> RootInclude: Clear pool, add root
 *
 * RootInclude: Temp pool of includes
 * RootInclude --> RootInclude: Add
 * RootInclude --> Process: Done
 *
 * Process: Temp pool to permanent pool
 * Process --> Waiting
 *
 * Finalize: strip includes
 * Finalize: Data ready to be used
 * @enduml
 *
 * Params:
 *  PayloadT = extra data associated with a particulare file such as the language.
 */
struct GenericTestDoubleIncludes(PayloadT) {
    import std.regex : Regex;
    import std.container : RedBlackTree;

    private enum State {
        waiting,
        symbolInclude,
        rootInclude,
        process,
        finalize,
        forceInclude
    }

    struct Include {
        string filename;
        PayloadT payload;
        alias filename this;
    }

    private {
        RedBlackTree!Include permanent_pool;
        Include[] work_pool;

        State st;
        Regex!char strip_incl;
        string[] unstripped_incls;
    }

    @disable this();

    this(Regex!char strip_incl) {
        import std.container : make;

        this.strip_incl = strip_incl;
        this.permanent_pool = make!(typeof(this.permanent_pool));
    }

    auto includes() @safe pure nothrow @nogc
    in {
        assert(st == State.finalize);
    }
    body {
        import std.algorithm : map;

        return permanent_pool[].map!(a => a.filename);
    }

    auto includesWithPayload() @safe pure nothrow @nogc
    in {
        assert(st == State.finalize);
    }
    body {
        return permanent_pool[];
    }

    /** Replace buffer of includes with argument.
     *
     * See description of states to understand what UserDefined entitles.
     *
     * TODO this contains a possible bug because the kind is not provided.
     */
    void forceIncludes(string[] in_incls) {
        import std.algorithm : each;

        st = State.forceInclude;

        /// Assuming user defined includes are good as they are so no stripping.
        () @trusted { in_incls.each!(a => permanent_pool.insert(Include(a))); }();
    }

    void finalize() @safe pure nothrow @nogc
    in {
        import std.algorithm : among;

        assert(st.among(State.waiting, State.forceInclude));
    }
    body {
        st = State.finalize;
    }

    void process() @safe
    in {
        import std.algorithm : among;

        assert(st.among(State.waiting, State.rootInclude, State.symbolInclude, State.forceInclude));
    }
    body {
        import std.algorithm : each;

        if (st == State.forceInclude)
            return;

        st = State.waiting;

        // no paths added, nothing to do
        if (work_pool.length == 0)
            return;

        () @trusted {
            stripIncl(work_pool, strip_incl).each!(a => permanent_pool.insert(a));
        }();
        work_pool.length = 0;
    }

    void put(string fname, LocationType type, PayloadT kind = PayloadT.init) @safe
    in {
        import std.utf : validate;

        validate((cast(string) fname));
    }
    body {
        auto val = Include(fname, kind);

        switch (st) with (State) {
        case waiting:
            work_pool ~= val;
            if (type == LocationType.Root) {
                st = rootInclude;
            } else {
                st = symbolInclude;
            }
            break;

        case rootInclude:
            st = rootInclude;
            if (type == LocationType.Root) {
                work_pool ~= val;
            }
            break;

        case symbolInclude:
            if (type == LocationType.Root) {
                work_pool = [val]; // root override previous pool values
                st = rootInclude;
            } else {
                work_pool ~= val;
            }
            break;

        case forceInclude:
            // ignore
            break;

        default:
            assert(0);
        }
    }

    string toString() @safe const {
        import std.exception : assumeUnique;

        char[] buf;
        buf.reserve(100);
        this.toString((const(char)[] s) { buf ~= s; });
        auto trustedUnique(T)(T t) @trusted {
            return assumeUnique(t);
        }

        return trustedUnique(buf);
    }

    void toString(Writer)(scope Writer w) const {
        import std.algorithm : copy, joiner, map;
        import std.ascii : newline;
        import std.conv : to;
        import std.range : chain, only;
        import std.range.primitives : put;

        put(w, st.to!string());
        put(w, newline);
        // dfmt off
        chain(work_pool.map!(a => cast(string) a),
              permanent_pool[].map!(a => cast(string) a))
            .joiner(newline)
            .copy(w);
        // dfmt on
    }
}

/// Use when no extra payload is needed.
alias TestDoubleIncludes = GenericTestDoubleIncludes!(DummyPayload);

/** Strip the filename with the regexp or if that fails use the input filename as is.
 */
T stripFile(T)(T fname, Regex!char re) @trusted {
    import std.array : appender;
    import std.algorithm : copy;
    import std.range : dropOne;
    import std.regex : matchFirst;

    if (re.empty) {
        return fname;
    }

    auto c = matchFirst(cast(string) fname, re);
    auto rval = fname;

    debug logger.tracef("input is '%s'. After strip: %s", fname, c);

    if (!c.empty) {
        auto app = appender!string();
        c.dropOne.copy(app);
        rval = app.data;
    }

    return rval;
}

/** Fixup the includes to be ready for usage as #include.
 *
 * Deduplicate.
 * Strip the includes according to the user supplied configuration.
 */
private T[] stripIncl(T)(ref T[] incls, Regex!char re) {
    import std.array : array;
    import std.algorithm : cache, map, filter;
    import cpptooling.utility : dedup;

    // dfmt off
    auto r = dedup(incls)
        .map!(a => stripFile(a, re))
        .filter!(a => a.length > 0)
        .array();
    // dfmt on

    return r;
}
