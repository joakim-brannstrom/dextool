/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.analyzer.clang.ast.attribute;

import std.meta : AliasSeq;

import deimos.clang.index : CXCursorKind;

import cpptooling.analyzer.clang.ast.node : Node, generateNodes;

abstract class Attribute : Node {
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
alias AttributeSeq = AliasSeq!(
    CXCursorKind.CXCursor_UnexposedAttr,
    CXCursorKind.CXCursor_IBActionAttr,
    CXCursorKind.CXCursor_IBOutletAttr,
    CXCursorKind.CXCursor_IBOutletCollectionAttr,
    CXCursorKind.CXCursor_CXXFinalAttr,
    CXCursorKind.CXCursor_CXXOverrideAttr,
    CXCursorKind.CXCursor_AnnotateAttr,
    CXCursorKind.CXCursor_AsmLabelAttr,
    CXCursorKind.CXCursor_PackedAttr,
    CXCursorKind.CXCursor_PureAttr,
    CXCursorKind.CXCursor_ConstAttr,
    CXCursorKind.CXCursor_NoDuplicateAttr,
    CXCursorKind.CXCursor_CUDAConstantAttr,
    CXCursorKind.CXCursor_CUDADeviceAttr,
    CXCursorKind.CXCursor_CUDAGlobalAttr,
    CXCursorKind.CXCursor_CUDAHostAttr,
    CXCursorKind.CXCursor_CUDASharedAttr,
    );
// dfmt on

mixin(generateNodes!(Attribute, AttributeSeq));
