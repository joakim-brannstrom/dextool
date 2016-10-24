// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module cpptooling.analyzer.clang.utility;

import std.typecons : Flag, Yes, No, Nullable;
import logger = std.experimental.logger;

import clang.Cursor : Cursor;
import clang.TranslationUnit : TranslationUnit;

import cpptooling.analyzer.clang.ast : Visitor;
import cpptooling.analyzer.clang.type : TypeResults;
import cpptooling.data.symbol.container : Container;

import deimos.clang.index : CXCursorKind;

version (unittest) {
    import unit_threaded : Name, shouldEqual;
} else {
    private struct Name {
        string name_;
    }
}

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

/// Determine if a kind affects the scope.
bool isScopeKind(CXCursorKind kind) @safe pure nothrow @nogc {
    switch (kind) with (CXCursorKind) {
    case CXCursor_ClassTemplate:
    case CXCursor_StructDecl:
    case CXCursor_UnionDecl:
    case CXCursor_ClassDecl:
    case CXCursor_CXXMethod:
    case CXCursor_FunctionDecl:
    case CXCursor_Constructor:
    case CXCursor_Destructor:
    case CXCursor_Namespace:
        return true;
    default:
        return false;
    }
}

/// Determine if a cursor is in the global or namespace scope.
bool isGlobalOrNamespaceScope(const(Cursor) c) @safe {
    import deimos.clang.index : CXCursorKind;

    // if the loop is never ran it is in the global namespace
    foreach (bt; c.backtrack) {
        if (bt.kind == CXCursorKind.CXCursor_Namespace) {
            // ok
        } else if (bt.kind.isScopeKind) {
            return false;
        }
    }

    return true;
}

//TODO remove the default value for indent.
void put(ref Nullable!TypeResults tr, ref Container container, in uint indent = 0) @safe {
    import std.range : chain, only;

    if (tr.isNull) {
        return;
    }

    foreach (a; chain(only(tr.primary), tr.extra)) {
        container.put(a.type.kind);
        container.put(a.location, a.type.kind.usr, a.type.attr.isDefinition);
    }
}

/** Check the context for diagnositc errors.
 *
 * Returns: True if errors where found.
 */
bool hasParseErrors(ref TranslationUnit tu) {
    import deimos.clang.index : CXDiagnosticSeverity;

    if (!tu.isValid)
        return true;

    auto dia = tu.diagnostics;

    foreach (diag; dia) {
        auto severity = diag.severity;

        final switch (severity) with (CXDiagnosticSeverity) {
        case CXDiagnostic_Ignored:
        case CXDiagnostic_Note:
        case CXDiagnostic_Warning:
            break;
        case CXDiagnostic_Error:
        case CXDiagnostic_Fatal:
            return true;
        }
    }

    return false;
}

/** Log diagnostic error messages to std.logger.
 *
 * TODO Change to a template with a sink as parameter.
 */
void logDiagnostic(ref TranslationUnit tu) {
    import logger = std.experimental.logger;

    import deimos.clang.index : CXDiagnosticSeverity;

    auto dia = tu.diagnostics;

    foreach (diag; dia) {
        auto severity = diag.severity;

        final switch (severity) with (CXDiagnosticSeverity) {
        case CXDiagnostic_Ignored:
            logger.info(diag.format);
            break;
        case CXDiagnostic_Note:
            logger.info(diag.format);
            break;
        case CXDiagnostic_Warning:
            logger.warning(diag.format);
            break;
        case CXDiagnostic_Error:
            logger.error(diag.format);
            break;
        case CXDiagnostic_Fatal:
            logger.error(diag.format);
            break;
        }
    }
}
