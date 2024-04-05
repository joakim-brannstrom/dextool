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
module libclang_ast.ast.expression;
import libclang_ast.ast.node : Node;

abstract class Expression : Node {
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

final class UnexposedExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class DeclRefExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class MemberRefExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CallExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class BlockExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class IntegerLiteral : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class FloatingLiteral : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ImaginaryLiteral : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class StringLiteral : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CharacterLiteral : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ParenExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class UnaryOperator : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ArraySubscriptExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class BinaryOperator : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CompoundAssignOperator : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ConditionalOperator : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CStyleCastExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CompoundLiteralExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class InitListExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class AddrLabelExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class StmtExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class GenericSelectionExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class GNUNullExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CXXStaticCastExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CXXDynamicCastExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CXXReinterpretCastExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CXXConstCastExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CXXFunctionalCastExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CXXTypeidExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CXXBoolLiteralExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CXXNullPtrLiteralExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CXXThisExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CXXThrowExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CXXNewExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CXXDeleteExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class UnaryExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class PackExpansionExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class SizeOfPackExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class LambdaExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class FixedPointLiteral : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CXXAddrspaceCastExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class ConceptSpecializationExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class RequiresExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}

final class CXXParenListInitExpr : Expression {
    import clang.Cursor : Cursor;

    this(scope Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(scope Visitor v) @safe const scope {
        static import libclang_ast.ast;

        libclang_ast.ast.accept(cursor, v);
    }
}
