/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.analyzer.clang.ast.statement;

import std.meta : AliasSeq;

import deimos.clang.index : CXCursorKind;

import cpptooling.analyzer.clang.ast.node : Node, generateNodes;

abstract class Statement : Node {
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
alias StatementSeq = AliasSeq!(
                               CXCursorKind.CXCursor_UnexposedStmt,
                               CXCursorKind.CXCursor_LabelStmt,
                               CXCursorKind.CXCursor_CompoundStmt,
                               CXCursorKind.CXCursor_CaseStmt,
                               CXCursorKind.CXCursor_DefaultStmt,
                               CXCursorKind.CXCursor_IfStmt,
                               CXCursorKind.CXCursor_SwitchStmt,
                               CXCursorKind.CXCursor_WhileStmt,
                               CXCursorKind.CXCursor_DoStmt,
                               CXCursorKind.CXCursor_ForStmt,
                               CXCursorKind.CXCursor_GotoStmt,
                               CXCursorKind.CXCursor_IndirectGotoStmt,
                               CXCursorKind.CXCursor_ContinueStmt,
                               CXCursorKind.CXCursor_BreakStmt,
                               CXCursorKind.CXCursor_ReturnStmt,
                               // overlaps with AsmStmt
                               //CXCursorKind.CXCursor_GCCAsmStmt,
                               CXCursorKind.CXCursor_AsmStmt,
                               CXCursorKind.CXCursor_ObjCAtTryStmt,
                               CXCursorKind.CXCursor_ObjCAtCatchStmt,
                               CXCursorKind.CXCursor_ObjCAtFinallyStmt,
                               CXCursorKind.CXCursor_ObjCAtThrowStmt,
                               CXCursorKind.CXCursor_ObjCAtSynchronizedStmt,
                               CXCursorKind.CXCursor_ObjCAutoreleasePoolStmt,
                               CXCursorKind.CXCursor_ObjCForCollectionStmt,
                               CXCursorKind.CXCursor_CXXCatchStmt,
                               CXCursorKind.CXCursor_CXXTryStmt,
                               CXCursorKind.CXCursor_CXXForRangeStmt,
                               CXCursorKind.CXCursor_SEHTryStmt,
                               CXCursorKind.CXCursor_SEHExceptStmt,
                               CXCursorKind.CXCursor_SEHFinallyStmt,
                               CXCursorKind.CXCursor_MSAsmStmt,
                               CXCursorKind.CXCursor_NullStmt,
                               CXCursorKind.CXCursor_DeclStmt,
                               );
// dfmt on

mixin(generateNodes!(Statement, StatementSeq));
