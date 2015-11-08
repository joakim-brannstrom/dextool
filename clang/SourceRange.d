/** Written in the D programming language.
 * Authors: Joakim Brännström (joakim.brannstrom dottli gmx.com)
 * Version: 1.1
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 * History:
 *  1.1 additional features missing compared to cindex.py. 2015-03-06 $(BR)
 *    Joakim Brännström
 */
module clang.SourceRange;

import std.conv;
import std.string;
import std.experimental.logger;

import deimos.clang.index;

import clang.SourceLocation;
import clang.Util;

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
    mixin CX;

    /// Retrieve a NULL (invalid) source range.
    static SourceRange empty() {
        auto r = clang_getNullRange();
        return SourceRange(r);
    }

    /// Retrieve a source location representing the first character within a source range.
    @property SourceLocation start() {
        auto r = clang_getRangeStart(cx);
        return SourceLocation(r);
    }

    /// Retrieve a source location representing the last character within a source range.
    @property SourceLocation end() {
        auto r = clang_getRangeEnd(cx);
        return SourceLocation(r);
    }

    ///
    bool isNull() {
        return clang_Range_isNull(cx) != 0;
    }

    ///
    equals_t opEquals(const ref SourceRange range2) const {
        return clang_equalRanges(cast(CXSourceRange) cx, cast(CXSourceRange) range2) != 0;
    }
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
