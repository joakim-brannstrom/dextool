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
module cpptooling.utility.range;

@nogc struct ArrayRange(T) {
    @property auto front() @safe pure nothrow {
        assert(!empty, "Can't get front of an empty range of " ~ T.stringof);
        return payload[0];
    }

    @property auto back() @safe pure nothrow {
        assert(!empty, "Can't get back of an empty range of " ~ T.stringof);
        return payload[$ - 1];
    }

    @property void popFront() @safe pure nothrow {
        assert(!empty, "Can't pop front of an empty range of " ~ T.stringof);
        payload = payload[1 .. $];
    }

    @property void popBack() @safe pure nothrow {
        assert(!empty, "Can't pop back of an empty range of " ~ T.stringof);
        payload = payload[0 .. $ - 1];
    }

    @property bool empty() @safe pure nothrow const {
        return payload.length == 0;
    }

    @property auto save() @safe pure nothrow {
        return typeof(this)(payload);
    }

private:
    T payload;
}

auto arrayRange(T)(T[] s) {
    return ArrayRange!(T[])(s);
}

private enum isArray(T) = is(T : T[]);
