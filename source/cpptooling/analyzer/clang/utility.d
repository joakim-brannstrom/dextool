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
import cpptooling.analyzer.clang.ast.visitor;
import cpptooling.analyzer.clang.type : TypeResult;
import cpptooling.data.symbol.container : Container;

version (unittest) {
    import unit_threaded : Name, shouldEqual;
} else {
    private struct Name {
        string name_;
    }
}

/** Travers a node tree and gather all paramdecl to an array.
 * Params:
 * cursor = A node containing ParmDecl nodes as children.
 * Example:
 * -----
 * class Simple{ Simple(char x, char y); }
 * -----
 * The AST for the above is kind of the following:
 * Example:
 * ---
 * Simple [CXCursor_Constructor Type(CXType(CXType_FunctionProto))
 *   x [CXCursor_ParmDecl Type(CXType(CXType_Char_S))
 *   y [CXCursor_ParmDecl Type(CXType(CXType_Char_S))
 * ---
 * It is translated to the array [("char", "x"), ("char", "y")].
 */
auto paramDeclTo(ref Cursor cursor, const ref Container container) {
    import cpptooling.analyzer.clang.type;
    import cpptooling.data.representation : TypeKindVariable, CppVariable,
        makeCxParam, CxParam, VariadicType;

    CxParam[] rval;

    auto type = cursor.type;
    auto params = extractParams2(cursor, type, container, 0);
    foreach (p; params) {
        rval ~= makeCxParam(TypeKindVariable(p.tka, CppVariable(p.id)));
    }

    debug {
        import std.variant : visit;

        foreach (p; rval) {
            // dfmt off
            () @trusted {
                p.visit!((TypeKindVariable p) => logger.trace(p.type.toStringDecl(cast(string) p.name)),
                         (TypeKindAttr p) => logger.trace(p.toStringDecl("x")),
                         (VariadicType p) => logger.trace("..."));
            }();
            // dfmt on
        }
    }

    return params;
}

void backtrackNode(T)(ref Cursor c, ref T callback, int depth = 0) {
    import std.range : repeat;

    auto curr = c;
    while (curr.isValid) {
        callback.apply(curr, depth);
        curr = curr.semanticParent;
        ++depth;
    }
}

void put(ref Nullable!TypeResult tr, ref Container container, in uint indent = 0) {
    import cpptooling.analyzer.clang.type : logTypeResult;

    if (!tr.isNull) {
        logTypeResult(tr, indent);
        container.put(tr.primary.kind);
        foreach (e; tr.extra) {
            container.put(e.kind);
        }
    }
}
