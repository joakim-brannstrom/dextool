#!/usr/bin/env dub
/+ dub.sdl:
name "generate_clang_ast_nodes"
lflags "-L/usr/lib/llvm-10/lib"
libs  ":libclang.so.1"
sourcePaths "source" "../libs/libclang/source"
+/
/**
Copyright: Copyright (c) 2016-2021, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module app;

import std.format : format;
import std.stdio : File;
import std.string : toLower, toUpper;

import libclang_ast.ast.nodes;

void main(string[] args) {
    generateNodeCode(AttributeSeq, "Attribute");
    generateNodeCode(DeclarationSeq, "Declaration");
    generateNodeCode(ExpressionSeq, "Expression");
    generateNodeCode(ExtraSeq, "Extra");
    generateNodeCode(PreprocessorSeq, "Preprocessor");
    generateNodeCode(ReferenceSeq, "Reference");
    generateNodeCode(StatementSeq, "Statement");

    struct SeqBase {
        immutable(string)[] seq;
        string base;
    }

    // dfmt off
    generateVisitorCode(
                        SeqBase(AttributeSeq, "Attribute"),
                        SeqBase(DeclarationSeq, "Declaration"),
                        SeqBase(ExpressionSeq, "Expression"),
                        SeqBase(ExtraSeq, "Extra"),
                        SeqBase(PreprocessorSeq, "Preprocessor"),
                        SeqBase(ReferenceSeq, "Reference"),
                        SeqBase(StatementSeq, "Statement"),
                        );
    // dfmt on
}

void generateNodeCode(Char)(Char[] seq, string name) {
    // template arguments
    // 0: the module name of the base node group.
    // 1: the name of the base module.
    // 2: data containing the specialized nodes.
    immutable template_ = `/**
Copyright: Copyright (c) Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

DO NOT EDIT. THIS FILE IS GENERATED.
See the generator script source/devtool/generator_clang_ast_nodes.d
*/
module libclang_ast.ast.%s;
import libclang_ast.ast.node : Node;

abstract class %s : Node {
    import clang.Cursor : Cursor;
    import libclang_ast.ast : Visitor;

    private Cursor cursor_;

    // trusted on the assumption that the node is scope allocated and all access to cursor is via a scoped ref.
    this(scope Cursor cursor) @trusted {
        this.cursor_ = cursor;
    }

    Cursor cursor() return const @safe {
        return Cursor(cursor_.cx);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;
        libclang_ast.ast.accept(cursor_, v);
    }
}

%s
`;

    string name_lower = name.toLower;

    auto file = File("../source/libclang_ast/ast/" ~ name_lower ~ ".d", "w");
    file.write(format(template_, name_lower, name, generateNodes(seq.dup, name)));
}

template generateNodeAccept() {
    enum generateNodeAccept = q{
    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;
        libclang_ast.ast.accept(cursor, v);
    }
};
}

template generateNodeCtor() {
    enum generateNodeCtor = q{
    import clang.Cursor : Cursor;
    this(scope Cursor cursor) @safe {
        super(cursor);
    }
};
}

string generateNodeClass(string kind, string base) {
    import std.format : format;

    return format(q{
final class %s : %s {%s%s}}, makeNodeClassName(kind), base,
            generateNodeCtor!(), generateNodeAccept!());
}

unittest {
    // @Name("Should be the mixin string of an AST node")

    // dfmt off
    generateNodeClass("CXCursorKind.unexposedDecl", "UtNode")
        .splitter('\n')
        .map!(a => a.strip)
        .shouldEqual(
    q{
        final class UnexposedDecl : UtNode {
            import clang.Cursor : Cursor;
            this(scope Cursor cursor) @safe {
                super(cursor);
            }

            override void accept(scope Visitor v) @safe const {
                static import libclang_ast.ast;
                libclang_ast.ast.accept(cursor, v);
            }
        }}.splitter('\n')
    .map!(a => a.strip));
    // dfmt on
}

string generateNodes(string[] seq, string base) {
    import std.meta : staticMap;
    import std.conv : to;

    string mixins;
    foreach (node; seq) {
        mixins ~= generateNodeClass(node, base);
        mixins ~= "\n";
    }

    return mixins;
}

unittest {
    // @Name("Should be the mixin string for many AST nodes")

    // dfmt off
    generateNodes(["unexposedDecl",
            "structDecl"], "UtNode")
        .splitter('\n')
        .map!(a => a.strip)
        .shouldEqualPretty(
    q{
        final class UnexposedDecl : UtNode {
            import clang.Cursor : Cursor;
            this(Cursor cursor) @safe {
                super(cursor);
            }

            override void accept(scope Visitor v) @safe const {
                static import libclang_ast.ast;
                libclang_ast.ast.accept(cursor, v);
            }
        }

        final class StructDecl : UtNode {
            import clang.Cursor : Cursor;
            this(Cursor cursor) @safe {
                super(cursor);
            }

            override void accept(scope Visitor v) @safe const {
                static import libclang_ast.ast;
                libclang_ast.ast.accept(cursor, v);
            }
        }
    }.splitter('\n')
    .map!(a => a.strip));
    // dfmt on
}

void generateVisitorCode(ARGS...)(ARGS args) {
    immutable template_ = `/**
Copyright: Copyright (c) 2016-2021, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

DO NOT EDIT. THIS FILE IS GENERATED.
See the generator script source/devtool/generator_clang_ast_nodes.d
*/
module libclang_ast.ast.base_visitor;
abstract class Visitor {
    import libclang_ast.ast;

@safe:

    /// Called when entering a node
    void incr() scope {
    }

    /// Called when leaving a node
    void decr() scope {
    }

    /// Only visist the node if the condition is true
    bool precondition() scope { return true; }

    void visit(scope const TranslationUnit) {
    }
%s
}
`;

    auto file = File("../source/libclang_ast/ast/base_visitor.d", "w");

    string visits;
    foreach (arg; args) {
        visits ~= generateVisit(arg.base, arg.seq);
    }

    file.write(format(template_, visits));
}

string generateVisit(string Base, immutable(string)[] E) {
    import std.format : format;

    string result = format(q{
    void visit(scope const %s) {}
}, Base);

    foreach (e; E) {

        result ~= format(q{
    void visit(scope const %s value) {
        visit(cast(const(%s)) value);
    }
}, makeNodeClassName(e), Base);
    }

    return result;
}

unittest {
    class Declaration {
    }

    // dfmt off
    generateVisit("Declaration", ["unexposedDecl",
                   "unionDecl"])
        .splitter('\n')
        .map!(a => a.strip)
        .array()
        .shouldEqualPretty([
                     "",
                     "void visit(scope const Declaration) {}",
                     "",
                     "void visit(scope const UnexposedDecl value) {",
                     "visit(cast(const(Declaration)) value);",
                     "}",
                     "",
                     "void visit(const UnionDecl value) {",
                     "visit(cast(const(Declaration)) value);",
                     "}",
                     ""
                     ]);
    // dfmt on
}
