/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.analyzer.clang.ast.reference;

import std.meta : AliasSeq;

import deimos.clang.index : CXCursorKind;

import cpptooling.analyzer.clang.ast.node : Node, generateNodes;

abstract class Reference : Node {
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
alias ReferenceSeq = AliasSeq!(
                               CXCursorKind.CXCursor_ObjCSuperClassRef,
                               CXCursorKind.CXCursor_ObjCProtocolRef,
                               CXCursorKind.CXCursor_ObjCClassRef,
                               CXCursorKind.CXCursor_TypeRef,
                               CXCursorKind.CXCursor_CXXBaseSpecifier,
                               CXCursorKind.CXCursor_TemplateRef,
                               CXCursorKind.CXCursor_NamespaceRef,
                               CXCursorKind.CXCursor_MemberRef,
                               CXCursorKind.CXCursor_LabelRef,
                               CXCursorKind.CXCursor_OverloadedDeclRef,
                               CXCursorKind.CXCursor_VariableRef,
                              );
// dfmt on

mixin(generateNodes!(Reference, ReferenceSeq));
