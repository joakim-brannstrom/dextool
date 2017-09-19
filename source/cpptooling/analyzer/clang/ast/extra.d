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
module cpptooling.analyzer.clang.ast.extra;
import cpptooling.analyzer.clang.ast.node : Node;

abstract class Extra : Node {
    import clang.Cursor : Cursor;
    import cpptooling.analyzer.clang.ast : Visitor;

    Cursor cursor;
    alias cursor this;

    this(Cursor cursor) @safe {
        this.cursor = cursor;
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}


final class ModuleImportDecl : Extra {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class TypeAliasTemplateDecl : Extra {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class StaticAssert : Extra {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class FriendDecl : Extra {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

