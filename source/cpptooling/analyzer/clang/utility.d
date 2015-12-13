// Written in the D programming language.
/**
Date: 2015, Joakim Brännström
License: GPL
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*/
module cpptooling.analyzer.clang.utility;

import logger = std.experimental.logger;

import clang.Cursor;

/** Travers a node tree and gather all paramdecl to an array.
 * Params:
 * T = Type that shall wrap TypeKindVariable.
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
auto paramDeclTo(Cursor cursor) {
    import cpptooling.analyzer.clang.type : TypeKind, translateType;
    import cpptooling.data.representation : TypeKindVariable, CppVariable,
        makeCxParam, CxParam, VariadicType;

    CxParam[] params;

    if (cursor.type.isTypedef) {
        // handles the following case.
        // typedef unsigned char (func_type) (const unsigned int baz);
        // extern func_ptr hest;
        // Must grab the underlying type and parse the arguments.
        // TODO investigate if the fixes to translateUnexposed can improve the
        // param extraction here to allow grabbing of the underlying types
        // identifier name.
        cursor = cursor.type.declaration;
        foreach (arg; cursor.type.func.arguments) {
            auto type = translateType(arg);
            params ~= makeCxParam(TypeKindVariable(type.unwrap, CppVariable("")));
        }
    } else {
        foreach (param; cursor.func.parameters) {
            auto type = translateType(param.type);
            params ~= makeCxParam(TypeKindVariable(type.unwrap, CppVariable(param.spelling)));
        }
    }

    if (cursor.func.isVariadic) {
        params ~= makeCxParam();
    }

    debug {
        import std.variant : visit;

        foreach (p; params) {
            // dfmt off
            () @trusted {
                p.visit!((TypeKindVariable p) => logger.trace(p.type.txt, ":", cast(string) p.name),
                         (TypeKind p) => logger.trace(p.txt),
                         (VariadicType p) => logger.trace("..."));
            }();
            // dfmt on
        }
    }

    return params;
}

import cpptooling.analyzer.clang.type;
import std.typecons : Tuple;

alias PTuple = Tuple!(WrapTypeKind, "wtk", string, "id");

//TODO duplicate code in paramDeclTo, reuse this implementation.
auto extractParams(Cursor cursor, bool is_variadic) {
    import std.typecons : tuple, Tuple;

    PTuple[] params;

    if (cursor.type.isTypedef) {
        // handles the following case.
        // typedef unsigned char (func_type) (const unsigned int baz);
        // extern func_ptr hest;
        // Must grab the underlying type and parse the arguments.
        // TODO investigate if the fixes to translateUnexposed can improve the
        // param extraction here to allow grabbing of the underlying types
        // identifier name.
        cursor = cursor.type.declaration;
        foreach (arg; cursor.type.func.arguments) {
            auto type = translateType(arg);
            params ~= PTuple(type, "");
        }
    } else {
        foreach (param; cursor.func.parameters) {
            auto type = translateType(param.type);
            params ~= PTuple(type, param.spelling);
        }
    }

    if (is_variadic) {
        auto wtk = WrapTypeKind();
        wtk.typeKind = makeTypeKind("", false, false, false);
        wtk.typeKind.info = TypeKind.SimpleInfo("%s");
        params ~= PTuple(wtk, "...");
    }

    debug {
        import std.variant : visit;

        foreach (p; params) {
            // dfmt off
            () @trusted {
                logger.trace(p.wtk.typeKind.txt, ":", cast(string) p.id);
            }();
            // dfmt on
        }
    }

    return params;
}

/// Join an array slice of PTuples to a parameter string of "type" "id"
string joinParamNames(PTuple[] r) @safe {
    import std.algorithm : joiner, map, filter;
    import std.conv : text;
    import std.range : enumerate;

    static string getTypeId(PTuple p, ulong uid) @trusted {
        import std.variant : visit;

        if (p.id == "") {
            return p.wtk.typeKind.toString("x" ~ text(uid));
        } else {
            return p.wtk.typeKind.toString(p.id);
        }
    }

    // using cache to avoid calling getName twice.
    return r.enumerate.map!(a => getTypeId(a.value, a.index)).filter!(a => a.length > 0).joiner(
        ", ").text();

}
