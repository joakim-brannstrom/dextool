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

import cpptooling.analyzer.clang.ast.visitor;
import cpptooling.analyzer.clang.type : TypeResults;
import cpptooling.data.symbol.container : Container;

version (unittest) {
    import unit_threaded : Name, shouldEqual;
} else {
    private struct Name {
        string name_;
    }
}

//TODO handle anonymous namespace
//TODO maybe merge with backtrackNode in clang/utility.d?
/** Analyze the scope the declaration/definition reside in by backtracking to
 * the root.
 *
 * TODO allow the caller to determine what cursor kind's are sent to the sink.
 */
void backtrackScope(NodeT, SinkT)(ref const(NodeT) node, scope SinkT sink) {
    import std.algorithm : among;
    import std.range.primitives : put;

    import deimos.clang.index : CXCursorKind;
    import cpptooling.analyzer.clang.type : logNode;

    static if (is(NodeT == Cursor)) {
        Cursor curr = node;
    } else {
        // a Declaration class
        // TODO add a constraint
        Cursor curr = node.cursor;
    }

    int depth = 0;
    while (curr.isValid) {
        debug logNode(curr, depth);

        if (curr.kind.among(CXCursorKind.CXCursor_UnionDecl, CXCursorKind.CXCursor_StructDecl,
                CXCursorKind.CXCursor_ClassDecl, CXCursorKind.CXCursor_Namespace)) {
            put(sink, curr.spelling);
        }

        curr = curr.semanticParent;
        ++depth;
    }
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
