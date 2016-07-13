/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.analyzer.clang.ast.directive;

import std.meta : AliasSeq;

import deimos.clang.index : CXCursorKind;

import cpptooling.analyzer.clang.ast.node : Node, generateNodes;

abstract class Directive : Node {
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
alias DirectiveSeq = AliasSeq!(
                               CXCursorKind.CXCursor_OMPParallelDirective,
                               CXCursorKind.CXCursor_OMPSimdDirective,
                               CXCursorKind.CXCursor_OMPForDirective,
                               CXCursorKind.CXCursor_OMPSectionsDirective,
                               CXCursorKind.CXCursor_OMPSectionDirective,
                               CXCursorKind.CXCursor_OMPSingleDirective,
                               CXCursorKind.CXCursor_OMPParallelForDirective,
                               CXCursorKind.CXCursor_OMPParallelSectionsDirective,
                               CXCursorKind.CXCursor_OMPTaskDirective,
                               CXCursorKind.CXCursor_OMPMasterDirective,
                               CXCursorKind.CXCursor_OMPCriticalDirective,
                               CXCursorKind.CXCursor_OMPTaskyieldDirective,
                               CXCursorKind.CXCursor_OMPBarrierDirective,
                               CXCursorKind.CXCursor_OMPTaskwaitDirective,
                               CXCursorKind.CXCursor_OMPFlushDirective,
                               CXCursorKind.CXCursor_SEHLeaveStmt,
                               CXCursorKind.CXCursor_OMPOrderedDirective,
                               CXCursorKind.CXCursor_OMPAtomicDirective,
                               CXCursorKind.CXCursor_OMPForSimdDirective,
                               CXCursorKind.CXCursor_OMPParallelForSimdDirective,
                               CXCursorKind.CXCursor_OMPTargetDirective,
                               CXCursorKind.CXCursor_OMPTeamsDirective,
                               CXCursorKind.CXCursor_OMPTaskgroupDirective,
                               CXCursorKind.CXCursor_OMPCancellationPointDirective,
                               CXCursorKind.CXCursor_OMPCancelDirective,
                               );
// dfmt on

mixin(generateNodes!(Directive, DirectiveSeq));
