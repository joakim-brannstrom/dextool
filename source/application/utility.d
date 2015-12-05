// Written in the D programming language.
/**
Date: 2015, Joakim Brännström
License: GPL
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
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
