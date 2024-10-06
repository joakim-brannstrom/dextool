/**
Copyright: Copyright (c) Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

DO NOT EDIT. THIS FILE IS GENERATED.
See the generator script source/devtool/generator_clang_ast_nodes.d
*/
module libclang_ast.ast.declaration;
import libclang_ast.ast.node : Node;

abstract class Declaration : Node {
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

final class UnexposedDecl : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class StructDecl : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class UnionDecl : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ClassDecl : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class EnumDecl : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class FieldDecl : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class EnumConstantDecl : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class FunctionDecl : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class VarDecl : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ParmDecl : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class TypedefDecl : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CXXMethod : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class Namespace : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class LinkageSpec : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class Constructor : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class Destructor : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ConversionFunction : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class TemplateTypeParameter : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class NonTypeTemplateParameter : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class TemplateTemplateParameter : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class FunctionTemplate : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ClassTemplate : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ClassTemplatePartialSpecialization : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class NamespaceAlias : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class UsingDirective : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class TypeAliasDecl : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CXXAccessSpecifier : Declaration {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}
