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

/** Includes intended for the test double.
 *
 * Filtered according to the user.
 *
 * TODO change to using a RedBlackTree to avoid duplications of files.
 *
 * States:
 *  - Normal.
 *      Start state.
 *      File are accepted and stored in buffer.
 *      Important that transitions FROM this state clears the internal buffer.
 *      Rational: The other states override data that was gathered during
 *      Normal.
 *  - HaveRoot.
 *      One or more roots have been found.
 *      Replaces all "Normal".
 *  - UserDefined.
 *      The user have supplied a list of includes which override any detected.
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
 * SymbolInclude --> SymbolClear: Add root
 *
 * SymbolClear: Clear temp pool
 * SymbolClear --> RootInclude: Add root
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
 */
struct TestDoubleIncludes {
    import std.regex : Regex;

    private enum State {
        Waiting,
        SymbolInclude,
        SymbolClear,
        RootInclude,
        Process,
        Finalize,
        ForceInclude
    }

    private {
        string[] permanent_pool;
        string[] work_pool;

        State st;
        Regex!char strip_incl;
        string[] unstripped_incls;
    }

    @disable this();

    this(Regex!char strip_incl) {
        this.strip_incl = strip_incl;
    }

    string[] includes() @safe pure nothrow @nogc
    in {
        assert(st == State.Finalize);
    }
    body {
        return permanent_pool;
    }

    /** Replace buffer of includes with argument.
     *
     * See description of states to understand what UserDefined entitles.
     */
    void forceIncludes(string[] in_incls) {
        st = State.ForceInclude;

        /// Assuming user defined includes are good as they are so no stripping.
        permanent_pool ~= in_incls;
    }

    void finalize() @safe pure nothrow @nogc
    in {
        import std.algorithm : among;

        assert(st.among(State.Waiting, State.ForceInclude));
    }
    body {
        st = State.Finalize;
    }

    void process() @safe
    in {
        import std.algorithm : among;

        assert(st.among(State.RootInclude, State.SymbolInclude));
    }
    body {
        st = State.Waiting;
        permanent_pool ~= stripIncl(work_pool, strip_incl);
        work_pool.length = 0;
    }

    void put(string fname, LocationType type) @safe
    in {
        import std.algorithm : among;
        import std.utf : validate;

        assert(st.among(State.Waiting, State.RootInclude, State.SymbolInclude, State.ForceInclude));
        validate((cast(string) fname));
    }
    body {
        switch (st) with (State) {
        case Waiting:
            work_pool ~= fname;
            if (type == LocationType.Root) {
                st = RootInclude;
            } else {
                st = SymbolInclude;
            }
            break;

        case RootInclude:
            st = RootInclude;
            if (type == LocationType.Root) {
                work_pool ~= fname;
            }
            break;

        case SymbolInclude:
            if (type == LocationType.Root) {
                work_pool = [fname]; // root override previous pool values
                st = RootInclude;
            } else {
                work_pool ~= fname;
            }
            break;

        case ForceInclude:
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
              permanent_pool.map!(a => cast(string) a))
            .joiner(newline)
            .copy(w);
        // dfmt on
    }
}

/** Strip the filename with the regexp or if that fails use the input filename as is.
 */
string stripFile(string fname, Regex!char re) @trusted {
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
private auto stripIncl(ref string[] incls, Regex!char re) {
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
