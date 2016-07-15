/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.analyzer.clang.ast.expression;

import std.meta : AliasSeq;

import deimos.clang.index : CXCursorKind;

import cpptooling.analyzer.clang.ast.node : Node, generateNodes;

abstract class Expression : Node {
    import clang.Cursor : Cursor;
    import cpptooling.analyzer.clang.ast.visitor : Visitor;

    Cursor cursor;
    alias cursor this;

    this(Cursor cursor) @safe {
        this.cursor = cursor;
    }

    import cpptooling.analyzer.clang.ast.node : generateNodeAccept;

    mixin(generateNodeAccept!());
}

// dfmt off
alias ExpressionSeq = AliasSeq!(
                                CXCursorKind.CXCursor_UnexposedExpr,
                                CXCursorKind.CXCursor_DeclRefExpr,
                                CXCursorKind.CXCursor_MemberRefExpr,
                                CXCursorKind.CXCursor_CallExpr,
                                CXCursorKind.CXCursor_ObjCMessageExpr,
                                CXCursorKind.CXCursor_BlockExpr,
                                CXCursorKind.CXCursor_IntegerLiteral,
                                CXCursorKind.CXCursor_FloatingLiteral,
                                CXCursorKind.CXCursor_ImaginaryLiteral,
                                CXCursorKind.CXCursor_StringLiteral,
                                CXCursorKind.CXCursor_CharacterLiteral,
                                CXCursorKind.CXCursor_ParenExpr,
                                CXCursorKind.CXCursor_UnaryOperator,
                                CXCursorKind.CXCursor_ArraySubscriptExpr,
                                CXCursorKind.CXCursor_BinaryOperator,
                                CXCursorKind.CXCursor_CompoundAssignOperator,
                                CXCursorKind.CXCursor_ConditionalOperator,
                                CXCursorKind.CXCursor_CStyleCastExpr,
                                CXCursorKind.CXCursor_CompoundLiteralExpr,
                                CXCursorKind.CXCursor_InitListExpr,
                                CXCursorKind.CXCursor_AddrLabelExpr,
                                CXCursorKind.CXCursor_StmtExpr,
                                CXCursorKind.CXCursor_GenericSelectionExpr,
                                CXCursorKind.CXCursor_GNUNullExpr,
                                CXCursorKind.CXCursor_CXXStaticCastExpr,
                                CXCursorKind.CXCursor_CXXDynamicCastExpr,
                                CXCursorKind.CXCursor_CXXReinterpretCastExpr,
                                CXCursorKind.CXCursor_CXXConstCastExpr,
                                CXCursorKind.CXCursor_CXXFunctionalCastExpr,
                                CXCursorKind.CXCursor_CXXTypeidExpr,
                                CXCursorKind.CXCursor_CXXBoolLiteralExpr,
                                CXCursorKind.CXCursor_CXXNullPtrLiteralExpr,
                                CXCursorKind.CXCursor_CXXThisExpr,
                                CXCursorKind.CXCursor_CXXThrowExpr,
                                CXCursorKind.CXCursor_CXXNewExpr,
                                CXCursorKind.CXCursor_CXXDeleteExpr,
                                CXCursorKind.CXCursor_UnaryExpr,
                                CXCursorKind.CXCursor_ObjCStringLiteral,
                                CXCursorKind.CXCursor_ObjCEncodeExpr,
                                CXCursorKind.CXCursor_ObjCSelectorExpr,
                                CXCursorKind.CXCursor_ObjCProtocolExpr,
                                CXCursorKind.CXCursor_ObjCBridgedCastExpr,
                                CXCursorKind.CXCursor_PackExpansionExpr,
                                CXCursorKind.CXCursor_SizeOfPackExpr,
                                CXCursorKind.CXCursor_LambdaExpr,
                                CXCursorKind.CXCursor_ObjCBoolLiteralExpr,
                                CXCursorKind.CXCursor_ObjCSelfExpr,
                                );
// dfmt on

mixin(generateNodes!(Expression, ExpressionSeq));
