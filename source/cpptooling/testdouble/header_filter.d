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
 */
struct TestDoubleIncludes {
    import std.regex : Regex;

    private enum State {
        Normal,
        HaveRoot,
        UserDefined
    }

    private {
        string[] incls;
        State st;
        Regex!char strip_incl;
        string[] unstripped_incls;
    }

    @disable this();

    this(Regex!char strip_incl) {
        this.strip_incl = strip_incl;
    }

    string[] includes() @safe pure nothrow @nogc {
        return incls;
    }

    /** Replace buffer of includes with argument.
     *
     * See description of states to understand what UserDefined entitles.
     */
    void forceIncludes(string[] in_incls) {
        st = State.UserDefined;
        foreach (incl; in_incls) {
            incls ~= incl;
        }
    }

    /// Assuming user defined includes are good as they are so no stripping.
    void doStrip() @safe {
        switch (st) with (State) {
        case Normal:
        case HaveRoot:
            incls = stripIncl(unstripped_incls, strip_incl);
            break;
        default:
        }
    }

    void put(string fname, LocationType type) @safe
    in {
        import std.utf : validate;

        validate((cast(string) fname));
    }
    body {
        final switch (st) with (State) {
        case Normal:
            if (type == LocationType.Root) {
                unstripped_incls = [fname];
                st = HaveRoot;
            } else {
                unstripped_incls ~= fname;
            }
            break;
        case HaveRoot:
            // only accepting roots
            if (type == LocationType.Root) {
                unstripped_incls ~= fname;
            }
            break;
        case UserDefined:
            // ignoring includes
            break;
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

        chain(only(st.to!string()), incls.map!(a => cast(string) a),
                unstripped_incls.map!(a => cast(string) a)).joiner(newline).copy(w);
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
