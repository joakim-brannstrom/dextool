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
module libclang_ast.ast.declaration;
import libclang_ast.ast.node : Node;

abstract class Declaration : Node {
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

final class UnexposedDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class StructDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class UnionDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ClassDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class EnumDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class FieldDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class EnumConstantDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class FunctionDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class VarDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ParmDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ObjCInterfaceDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ObjCCategoryDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ObjCProtocolDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ObjCPropertyDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ObjCIvarDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ObjCInstanceMethodDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ObjCClassMethodDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ObjCImplementationDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ObjCCategoryImplDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class TypedefDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CxxMethod : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class Namespace : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class LinkageSpec : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class Constructor : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class Destructor : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ConversionFunction : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class TemplateTypeParameter : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class NonTypeTemplateParameter : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class TemplateTemplateParameter : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class FunctionTemplate : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ClassTemplate : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ClassTemplatePartialSpecialization : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class NamespaceAlias : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class UsingDirective : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class TypeAliasDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ObjCSynthesizeDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ObjCDynamicDecl : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CxxAccessSpecifier : Declaration {
    import clang.Cursor : Cursor;

    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}
