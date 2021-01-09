/**
Copyright: Copyright (c) 2015-2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module clang.SourceRange;

import std.conv;
import std.string;
import std.experimental.logger;

import clang.c.Index;

import clang.SourceLocation;

///
struct SourceRange {
    import std.format : FormatSpec;
    import clang.Util;

    mixin CX;

    /// Retrieve a NULL (invalid) source range.
    static SourceRange empty() @trusted {
        auto r = clang_getNullRange();
        return SourceRange(r);
    }

    /// Retrieve a source location representing the first character within a source range.
    @property SourceLocation start() const @trusted {
        auto r = clang_getRangeStart(cx);
        return SourceLocation(r);
    }

    /// Retrieve a source location representing the last character within a source range.
    @property SourceLocation end() const @trusted {
        auto r = clang_getRangeEnd(cx);
        return SourceLocation(r);
    }

    @property string path() const @trusted {
        return start.path;
    }

    ///
    bool isNull() const @trusted {
        return clang_Range_isNull(cx) != 0;
    }

    ///
    equals_t opEquals(const ref SourceRange range2) const {
        return clang_equalRanges(cast(CXSourceRange) cx, cast(CXSourceRange) range2) != 0;
    }

    string toString() @safe const {
        import std.exception : assumeUnique;
        import std.format : FormatSpec;

        char[] buf;
        buf.reserve(100);
        auto fmt = FormatSpec!char("%s");
        toString((const(char)[] s) { buf ~= s; }, fmt);
        auto trustedUnique(T)(T t) @trusted {
            return assumeUnique(t);
        }

        return trustedUnique(buf);
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        import std.format : formattedWrite;

        auto start = this.start.presumed;
        auto end = this.end.presumed;

        if (isValid) {
            formattedWrite(w, "%s [start='%s:%s' end='%s:%s']", start.file,
                    start.line, start.column, end.line, end.column);
        } else {
            formattedWrite(w, "%s(%s)", typeid(this), cx);
        }
    }
}

/** Check if two source ranges intersect
 *
 * Implementation by Wojciech Szęszoł, Feb 14 2016.
 */
bool intersects(in SourceRange a, in SourceRange b) {
    static bool test(uint begin, uint end, uint p) {
        return p >= begin && p <= end;
    }

    return a.path == b.path && (test(a.start.offset, a.end.offset,
            b.start.offset) || test(a.start.offset, a.end.offset,
            b.end.offset) || test(b.start.offset, b.end.offset,
            a.start.offset) || test(b.start.offset, b.end.offset, a.end.offset));
}

/// Retrieve a source range given the beginning and ending source locations.
SourceRange range(ref SourceLocation begin, SourceLocation end) {
    auto r = clang_getRange(begin.cx, end.cx);
    return SourceRange(r);
}

unittest {
    // Test of null range.
    auto r = SourceRange.empty();

    assert(r.isNull == true);
}
