/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.analyzer.clang.ast.node;

import deimos.clang.index : CXCursorKind;

version (unittest) {
    import std.algorithm : map, splitter;
    import std.array : array;
    import std.string : strip;
    import unit_threaded : Name, shouldEqual;
    import test.extra_should : shouldEqualPretty;
} else {
    private struct Name {
        string name_;
    }
}

interface Node {
    import cpptooling.analyzer.clang.ast.visitor : Visitor;

public:
    void accept(Visitor visitor) const;
}

private enum CXCursorKind_PrefixLen = "CXCursor_".length;

template generateNodeAccept() {
    enum generateNodeAccept = q{
            override void accept(Visitor v) @safe const {
                static import cpptooling.analyzer.clang.ast;
                cpptooling.analyzer.clang.ast.accept(cursor, v);
            }
        };
}

template generateNodeCtor() {
    enum generateNodeCtor = q{
            import clang.Cursor : Cursor;
            this(Cursor cursor) @safe {
                super(cursor);
            }
        };
}

template generateNodeClass(Base, alias kind) {
    import std.format : format;
    import std.conv : to;

    enum k_str = kind.stringof[CXCursorKind_PrefixLen .. $];
    enum generateNodeClass = format(q{
        final class %s : %s {%s%s}}, k_str, Base.stringof,
                generateNodeCtor!(), generateNodeAccept!());
}

@Name("Should be the mixin string of an AST node")
unittest {
    class UtNode {
    }

    // dfmt off
    generateNodeClass!(UtNode, CXCursorKind.CXCursor_UnexposedDecl)
        .splitter('\n')
        .map!(a => a.strip)
        .shouldEqualPretty(
    q{
        final class UnexposedDecl : UtNode {
            import clang.Cursor : Cursor;
            this(Cursor cursor) @safe {
                super(cursor);
            }

            override void accept(Visitor v) @safe const {
                static import cpptooling.analyzer.clang.ast;
                cpptooling.analyzer.clang.ast.accept(cursor, v);
            }
        }}.splitter('\n')
    .map!(a => a.strip));
    // dfmt on
}

string generateNodes(Base, E...)() {
    import std.meta : staticMap;
    import std.conv : to;

    alias dummyNode(alias kind) = generateNodeClass!(Base, kind);

    string mixins;
    foreach (n; staticMap!(dummyNode, E)) {
        mixins ~= n;
        mixins ~= "\n";
    }

    return mixins;
}

@Name("Should be the mixin string for many AST nodes")
unittest {
    class UtNode {
    }

    // dfmt off
    generateNodes!(UtNode, CXCursorKind.CXCursor_UnexposedDecl,
            CXCursorKind.CXCursor_StructDecl)
        .splitter('\n')
        .map!(a => a.strip)
        .shouldEqualPretty(
    q{
        final class UnexposedDecl : UtNode {
            import clang.Cursor : Cursor;
            this(Cursor cursor) @safe {
                super(cursor);
            }

            override void accept(Visitor v) @safe const {
                static import cpptooling.analyzer.clang.ast;
                cpptooling.analyzer.clang.ast.accept(cursor, v);
            }
        }

        final class StructDecl : UtNode {
            import clang.Cursor : Cursor;
            this(Cursor cursor) @safe {
                super(cursor);
            }

            override void accept(Visitor v) @safe const {
                static import cpptooling.analyzer.clang.ast;
                cpptooling.analyzer.clang.ast.accept(cursor, v);
            }
        }
    }.splitter('\n')
    .map!(a => a.strip));
    // dfmt on
}
