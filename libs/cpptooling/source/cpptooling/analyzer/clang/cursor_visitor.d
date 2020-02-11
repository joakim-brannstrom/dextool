/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.analyzer.clang.cursor_visitor;

import clang.Cursor : Cursor;

private @safe nothrow struct ASTCursor {
    Cursor cursor;
    size_t depth;

    alias cursor this;
}

/**
 */
private @safe nothrow struct AST_BreathFirstResult {
    import std.container : Array;

    private int depth_;
    private typeof(Array!(Cursor).opSlice()) r;
    // index 0: the current range that is operated on.
    // index 1: the next one that is being filled with data.
    private Array!(Cursor)[] data;

    this(Cursor c) @trusted {
        data ~= Array!Cursor();
        data ~= Array!Cursor();
        data[0].insertBack(c);
        r = data[0][];
    }

    ASTCursor front() @safe nothrow const {
        assert(!empty, "Can't get front of an empty range");

        return ASTCursor(r.front, depth_);
    }

    void popFront() @trusted {
        assert(!empty, "Can't pop front of an empty range");

        import clang.Visitor;

        foreach (cursor, _; Visitor(r.front)) {
            data[1].insertBack(cursor);
        }

        r.popFront;

        if (r.length == 0) {
            data = data[1 .. $];
            r = data[0][];
            data ~= Array!Cursor();
            ++depth_;
        }
    }

    bool empty() @safe nothrow const {
        return r.empty && data[1].empty;
    }

    int depth() {
        return depth_;
    }
}

/** opApply compatible visitor of the clang AST, breath first.
 *
 * Example:
 * ---
 * foreach (child; c.visitBreathFirst.until!(a => a.depth == 3)) {
 *      if (child.kind == CXCursorKind.CXCursor_StructDecl) {
 *      ...
 *      }
 * }
 * ---
 */
auto visitBreathFirst(Cursor c) @trusted {
    return AST_BreathFirstResult(c);
}

private @safe nothrow struct AST_DepthFirstResult {
    static import std.array;
    import std.array : appender;
    import std.container : Array;
    import dextool.set : Set;

    //private Array!(Cursor) stack;
    // keeps the first node for each level of nodes that is traversed.
    //private Set!Cursor depth_;
    private Cursor[][] stack;

    this(Cursor c) @trusted {
        stack ~= [c];
    }

    ASTCursor front() @safe nothrow const {
        assert(!empty, "Can't get front of an empty range");
        return ASTCursor(stack[$ - 1][0], depth);
    }

    void popFront() @trusted {
        assert(!empty, "Can't pop front of an empty range");
        import clang.Visitor;

        void popEmpty() {
            while (!std.array.empty(stack) && std.array.empty(stack[$ - 1])) {
                stack = stack[0 .. $ - 1];
            }
        }

        popEmpty;

        auto f = stack[$ - 1][0];
        stack[$ - 1] = stack[$ - 1][1 .. $];

        auto app = appender!(Cursor[])();
        foreach (cursor, _; Visitor(f)) {
            app.put(cursor);
        }
        if (!std.array.empty(app.data)) {
            stack ~= app.data;
        }

        popEmpty;
    }

    bool empty() @safe nothrow const {
        return std.array.empty(stack);
    }

    size_t depth() @safe pure nothrow const @nogc {
        return stack.length;
    }
}

/** opApply compatible visitor of the clang AST, breath first.
 *
 * Example:
 * ---
 * foreach (child; c.visitBreathFirst.until!(a => a.depth == 3)) {
 *      if (child.kind == CXCursorKind.CXCursor_StructDecl) {
 *      ...
 *      }
 * }
 * ---
 */
auto visitDepthFirst(Cursor c) @trusted {
    return AST_DepthFirstResult(c);
}
