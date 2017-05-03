/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.analyzer.clang.cursor_backtrack;

import clang.Cursor : Cursor;

import deimos.clang.index : CXCursorKind;

private struct BacktrackResult {
    private Cursor cursor;

    Cursor front() @safe nothrow const {
        assert(!empty, "Can't get front of an empty range");

        return cursor;
    }

    void popFront() @safe {
        assert(!empty, "Can't pop front of an empty range");

        cursor = cursor.semanticParent;
    }

    bool empty() @safe nothrow const {
        try {
            return !cursor.isValid;
        }
        catch (Exception ex) {
        }

        return true;
    }
}

/** Analyze the scope the declaration/definition reside in by backtracking to
 * the root.
 */
auto backtrackScopeRange(NodeT)(const(NodeT) node) {
    static if (is(NodeT == Cursor)) {
        Cursor c = node;
    } else {
        // a Declaration class
        // TODO add a constraint
        Cursor c = node.cursor;
    }

    import std.algorithm : among, filter;
    import deimos.clang.index : CXCursorKind;

    return BacktrackResult(c).filter!(a => a.kind.among(CXCursorKind.CXCursor_UnionDecl,
            CXCursorKind.CXCursor_StructDecl, CXCursorKind.CXCursor_ClassDecl,
            CXCursorKind.CXCursor_Namespace));
}

/// Backtrack a cursor until the top cursor is reached.
auto backtrack(NodeT)(const(NodeT) node) {
    static if (is(NodeT == Cursor)) {
        Cursor c = node;
    } else {
        // a Declaration class
        // TODO add a constraint
        Cursor c = node.cursor;
    }

    return BacktrackResult(c);
}

/// Determine if a kind creates a local scope.
bool isLocalScope(CXCursorKind kind) @safe pure nothrow @nogc {
    switch (kind) with (CXCursorKind) {
    case CXCursor_ClassTemplate:
    case CXCursor_StructDecl:
    case CXCursor_UnionDecl:
    case CXCursor_ClassDecl:
    case CXCursor_CXXMethod:
    case CXCursor_FunctionDecl:
    case CXCursor_Constructor:
    case CXCursor_Destructor:
        return true;
    default:
        return false;
    }
}

/// Determine if a cursor is in the global or namespace scope.
bool isGlobalOrNamespaceScope(const(Cursor) c) @safe {
    import std.algorithm : among;
    import deimos.clang.index : CXCursorKind;

    // if the loop is never ran it is in the global namespace
    foreach (bt; c.backtrack) {
        if (bt.kind.among(CXCursorKind.CXCursor_Namespace, CXCursorKind.CXCursor_TranslationUnit)) {
            return true;
        } else if (bt.kind.isLocalScope) {
            return false;
        }
    }

    return false;
}
