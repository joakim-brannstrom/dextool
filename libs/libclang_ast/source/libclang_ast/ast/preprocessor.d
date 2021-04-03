/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

DO NOT EDIT. THIS FILE IS GENERATED.
See the generator script source/devtool/generator_clang_ast_nodes.d
*/
module libclang_ast.ast.preprocessor;
import libclang_ast.ast.node : Node;

abstract class Preprocessor : Node {
    import clang.Cursor : Cursor;
    import libclang_ast.ast : Visitor;

    Cursor cursor;
    alias cursor this;

    this(Cursor cursor) @safe {
        this.cursor = cursor;
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class PreprocessingDirective : Preprocessor {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class MacroDefinition : Preprocessor {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class MacroExpansion : Preprocessor {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class InclusionDirective : Preprocessor {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}
