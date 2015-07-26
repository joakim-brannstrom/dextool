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
module generator.analyze.wip;

import std.traits : ReturnType;

import clang.Cursor;
import clang.Visitor : Visitor;

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

/** Traverses a clang AST.
 * Required functions of VisitorType:
 *   void applyRoot(ref Cursor root). Called with the root node.
 *   bool apply(ref Cursor child, ref Cursor parent). Called for all nodes under root.
 * Optional functions:
 *   void incr(). Called before descending a node.
 *   void decr(). Called after ascending a node.
 */
void visitAst(VisitorT)(ref Cursor cursor, ref VisitorT v) if (
        hasApply!VisitorT && hasApplyRoot!VisitorT) {
    enum NodeType {
        Root,
        Child
    }

    static void helperVisitAst(NodeType NodeT)(ref Cursor child, ref Cursor parent,
        ref VisitorT v) {
        static if (__traits(hasMember, VisitorT, "incr")) {
            v.incr();
        }

        bool descend;

        // Root has no parent.
        static if (NodeT == NodeType.Root) {
            v.applyRoot(child);
            descend = true;
        }
        else {
            descend = v.apply(child, parent);
        }

        if (!child.isEmpty && descend) {
            foreach (child_, parent_; Visitor(child)) {
                helperVisitAst!(NodeType.Child)(child_, parent_, v);
            }
        }

        static if (__traits(hasMember, VisitorT, "decr")) {
            v.decr();
        }
    }

    helperVisitAst!(NodeType.Root)(cursor, cursor, v);
}

private:
enum hasApply(T) = __traits(hasMember, T, "apply") && is(ReturnType!(T.apply) == bool);
enum hasApplyRoot(T) = __traits(hasMember, T, "applyRoot") && is(ReturnType!(T.applyRoot) == void);
