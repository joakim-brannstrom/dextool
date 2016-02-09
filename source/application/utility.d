// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module application.utility;

import std.regex : Regex;
import std.stdio : File;
import std.typecons : Unique;
import logger = std.experimental.logger;

import application.types;

///TODO don't catch Exception, catch the specific.
auto tryOpenFile(string filename, string mode) @trusted nothrow {
    import std.exception;
    import std.typecons : Unique;

    Unique!File rval;

    try {
        rval = Unique!File(new File(filename, mode));
    }
    catch (Exception ex) {
    }
    if (rval.isEmpty) {
        try {
            logger.errorf("Unable to read/write file '%s'", filename);
        }
        catch (Exception ex) {
        }
    }

    return rval;
}

///TODO don't catch Exception, catch the specific.
auto tryWriting(string fname, string data) @trusted nothrow {
    import std.exception;

    static auto action(string fname, string data) {
        auto f = tryOpenFile(fname, "w");

        if (f.isEmpty) {
            return ExitStatusType.Errors;
        }
        scope (exit)
            f.close();

        f.write(data);

        return ExitStatusType.Ok;
    }

    auto status = ExitStatusType.Errors;

    try {
        status = action(fname, data);
    }
    catch (Exception ex) {
    }

    try {
        final switch (status) with (ExitStatusType) {
        case Ok:
            break;
        case Errors:
            logger.error("Failed to write to file ", fname);
            break;
        }
    }
    catch (Exception ex) {
    }

    return status;
}

///TODO move to clang module.
auto prependLangFlagIfMissing(string[] in_cflags) {
    import std.algorithm : findAmong;

    auto v = findAmong(in_cflags, ["-xc", "-xc++"]);

    if (v is null) {
        return ["-xc"] ~ in_cflags;
    }

    return in_cflags.dup;
}

unittest {
    import test.helpers : shouldEqualPretty;

    auto cflags = ["-DBEFORE", "-xc++", "-DAND_A_DEFINE", "-I/3906164"];
    cflags.shouldEqualPretty(prependLangFlagIfMissing(cflags));
}

/// if no regexp or no match when using the regexp, using the include
/// path as-is.
auto stripIncl(FileName incl, Regex!char re) @trusted {
    import std.array : array;
    import std.algorithm : joiner;
    import std.range : dropOne;
    import std.regex : matchFirst;
    import std.utf : byChar;

    auto c = matchFirst(cast(string) incl, re);
    auto rval = incl;
    logger.tracef("for input '%s', --strip-incl match is: %s", cast(string) incl, c);
    if (!c.empty) {
        rval = FileName(cast(string) c.dropOne.joiner("").byChar.array());
    }

    return rval;
}

auto stripIncl(ref FileName[] incls, Regex!char re) {
    import std.array : array;
    import std.algorithm : cache, map, filter;
    import cpptooling.data.representation : dedup;

    // dfmt off
    auto r = dedup(incls)
        .map!(a => stripIncl(a, re))
        .cache()
        .filter!(a => a.length > 0)
        .array();
    // dfmt on

    return r;

}

/** Includes intended for the test double. Filtered according to the user.
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
struct TdIncludes {
    import std.regex;

    enum State {
        Normal,
        HaveRoot,
        UserDefined
    }

    FileName[] incls;
    State st;
    Regex!char strip_incl;
    private FileName[] unstripped_incls;

    @disable this();

    this(Regex!char strip_incl) {
        this.strip_incl = strip_incl;
    }

    /** Replace buffer of includes with argument.
     *
     * See description of states to understand what UserDefined entitles.
     */
    void forceIncludes(string[] in_incls) {
        st = State.UserDefined;
        foreach (incl; in_incls) {
            incls ~= FileName(incl);
        }
    }

    void doStrip() @safe {
        incls ~= stripIncl(unstripped_incls, strip_incl);
    }

    void put(FileName fname, LocationType type) @safe {
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
            // ignoring new includes
            break;
        }
    }
}
