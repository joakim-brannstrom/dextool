// Written in the D programming language.
/**
Copyright: Copyright (c) 2015-2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module clang.SourceRange;

import std.conv;
import std.string;
import std.experimental.logger;

import deimos.clang.index;

import clang.SourceLocation;

string toString(SourceRange value) {
    import std.string;
    import std.conv;

    auto start = value.start;
    auto end = value.end;

    if (value.isValid) {
        return format("%s [start='%s' end='%s']", text(value.cx),
                text(start.presumed), text(end.presumed));
    }

    return format("%s(%s)", text(typeid(value)), text(value.cx));
}

///
struct SourceRange {
    import clang.Util;

    mixin CX;

    /// Retrieve a NULL (invalid) source range.
    static SourceRange empty() {
        auto r = clang_getNullRange();
        return SourceRange(r);
    }

    /// Retrieve a source location representing the first character within a source range.
    @property SourceLocation start() const {
        auto r = clang_getRangeStart(cx);
        return SourceLocation(r);
    }

    /// Retrieve a source location representing the last character within a source range.
    @property SourceLocation end() const {
        auto r = clang_getRangeEnd(cx);
        return SourceLocation(r);
    }

    @property string path() const {
        return start.path;
    }

    ///
    bool isNull() const {
        return clang_Range_isNull(cx) != 0;
    }

    ///
    equals_t opEquals(const ref SourceRange range2) const {
        return clang_equalRanges(cast(CXSourceRange) cx, cast(CXSourceRange) range2) != 0;
    }
}

/** Check if two source ranges intersect
 *
 * Implementation by Wojciech Szęszoł, Feb 14 2016.
 */
bool intersects(in SourceRange a, in SourceRange b) {
    return a.path == b.path && (a.start.offset <= b.start.offset
            && b.start.offset < a.end.offset) || (a.start.offset < b.end.offset
            && b.end.offset <= a.end.offset);
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
