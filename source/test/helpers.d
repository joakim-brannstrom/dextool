/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// This program is free software; you can redistribute it and/or modify
/// it under the terms of the GNU General Public License as published by
/// the Free Software Foundation; either version 2 of the License, or
/// (at your option) any later version.
///
/// This program is distributed in the hope that it will be useful,
/// but WITHOUT ANY WARRANTY; without even the implied warranty of
/// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
/// GNU General Public License for more details.
///
/// You should have received a copy of the GNU General Public License
/// along with this program; if not, write to the Free Software
/// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
module test.helpers;
import unit_threaded;

/**
 * Verify that two values are the same.
 * Useful when the values can be treated as ranges.
 * Throws: UnitTestException on failure
 */
void shouldEqualPretty(V, E)(V value, E expected, in string file = __FILE__, in ulong line = __LINE__) {
    import std.algorithm : count;
    import std.range : zip;
    import unit_threaded : shouldEqual;

    foreach (val, exp; zip(value, expected)) {
        shouldEqual(val, exp, file, line);
    }

    shouldEqual(count(value), count(expected), file, line);
}

/**
 * Verify that two strings are the same.
 * Performs a tests per line to better isolate when a difference is found.
 * Throws: UnitTestException on failure
 */
void shouldEqualPretty(string value, string expected, in string file = __FILE__,
    in ulong line = __LINE__) {
    import std.algorithm : splitter;
    import std.ascii : newline;

    auto rValue = value.splitter(newline);
    auto rExpected = expected.splitter(newline);

    shouldEqualPretty(rValue, rExpected, file, line);
}
