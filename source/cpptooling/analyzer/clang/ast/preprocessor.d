/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.analyzer.clang.ast.preprocessor;

import std.meta : AliasSeq;

import deimos.clang.index : CXCursorKind;

import cpptooling.analyzer.clang.ast.node : Node, generateNodes;

abstract class Preprocessor : Node {
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
alias PreprocessorSeq = AliasSeq!(
                                  CXCursorKind.CXCursor_PreprocessingDirective,
                                  CXCursorKind.CXCursor_MacroDefinition,
                                  CXCursorKind.CXCursor_MacroExpansion,
                                  // Overlaps with MacroExpansion
                                  //CXCursorKind.CXCursor_MacroInstantiation,
                                  CXCursorKind.CXCursor_InclusionDirective,
                                  );
// dfmt on

mixin(generateNodes!(Preprocessor, PreprocessorSeq));
