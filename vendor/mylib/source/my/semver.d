/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

A type that holds a semantic version that provide ordering and easy
construction from a plain `string`.
*/
module my.semver;

@safe:

/** A parsed semantic version.
 *
 * Currently only supports the numbering, no metadata after a `+`-sign.
 */
struct SemVer {
    import std.range : isOutputRange;

    private int[3] value_;

    /// Returns: major version number (first number).
    int major() pure nothrow const @nogc {
        return value_[0];
    }

    /// Returns: minor version number (second number).
    int minor() pure nothrow const @nogc {
        return value_[1];
    }

    /// Returns: bugfix version number (third number).
    int bugFix() pure nothrow const @nogc {
        return value_[2];
    }

    ///
    int opCmp(const SemVer rhs) pure nothrow const @nogc {
        foreach (i; 0 .. value_.length) {
            if (value_[i] < rhs.value_[i])
                return -1;
            if (value_[i] > rhs.value_[i])
                return 1;
        }
        return 0;
    }

    ///
    bool opEquals(const SemVer x) pure nothrow const @nogc {
        return value_ == x.value_;
    }

    ///
    bool opEquals(const int[] x) pure nothrow const @nogc {
        return value_[] == x;
    }

    ///
    string toString() @safe pure const {
        import std.array : appender;

        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    ///
    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        import std.format : formattedWrite;

        formattedWrite(w, "%s.%s.%s", value_[0], value_[1], value_[2]);
    }
}

/** Convert a string to a `SemVer`.
 *
 * An invalid `string` is returned as a `SemVer` with version `0.0.0`.
 */
SemVer toSemVer(string s) {
    import std.algorithm : filter;
    import std.array : empty;
    import std.conv : to;
    import std.range : dropOne, enumerate;
    import std.regex : regex, matchFirst;

    SemVer rval;

    const re = regex(`^(?:(\d+)\.)?(?:(\d+)\.)?(\d+)$`);
    auto m = matchFirst(s, re);
    if (m.empty)
        return rval;

    try {
        foreach (a; m.dropOne.filter!(a => !a.empty).enumerate) {
            rval.value_[a.index] = a.value.to!int;
        }
    } catch (Exception e) {
    }

    return rval;
}

/// Example.
unittest {
    import std.stdio : writeln;

    assert(toSemVer("1.2.3") == [1, 2, 3]);
    assert(toSemVer("1.2") == [1, 2, 0]);
    assert(toSemVer("1") == [1, 0, 0]);
    assert(toSemVer("1.2.3.4") == [0, 0, 0]);
}
