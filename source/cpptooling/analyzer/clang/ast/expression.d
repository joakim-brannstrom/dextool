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
module cpptooling.analyzer.clang.ast.expression;
import cpptooling.analyzer.clang.ast.node : Node;

abstract class Expression : Node {
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


final class UnexposedExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class DeclRefExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class MemberRefExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CallExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ObjCMessageExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class BlockExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class IntegerLiteral : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class FloatingLiteral : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ImaginaryLiteral : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class StringLiteral : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CharacterLiteral : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ParenExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class UnaryOperator : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ArraySubscriptExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class BinaryOperator : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CompoundAssignOperator : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ConditionalOperator : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CStyleCastExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CompoundLiteralExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class InitListExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class AddrLabelExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class StmtExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class GenericSelectionExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class GnuNullExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CxxStaticCastExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CxxDynamicCastExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CxxReinterpretCastExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CxxConstCastExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CxxFunctionalCastExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CxxTypeidExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CxxBoolLiteralExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CxxNullPtrLiteralExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CxxThisExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CxxThrowExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CxxNewExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class CxxDeleteExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class UnaryExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ObjCStringLiteral : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ObjCEncodeExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ObjCSelectorExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ObjCProtocolExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ObjCBridgedCastExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class PackExpansionExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class SizeOfPackExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class LambdaExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ObjCBoolLiteralExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

final class ObjCSelfExpr : Expression {
    import clang.Cursor : Cursor;
    this(Cursor cursor) @safe {
        super(cursor);
    }

    override void accept(Visitor v) @safe const {
        static import cpptooling.analyzer.clang.ast;
        cpptooling.analyzer.clang.ast.accept(cursor, v);
    }
}

