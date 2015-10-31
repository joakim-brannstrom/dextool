/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// This program is free software; you can redistribute it and/or modify
/// it under the terms of the GNU General Public License as published by
/// the Free Software Foundation; either version 2 of the License, or
/// (at your option) any later version.
///
/// This program is distributed in the hope that it will be useful,
/// but WITHOUT ANY WARRANTY; without even the implied warranty of
/// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
/// GNU General Public License for more details.
///
/// You should have received a copy of the GNU General Public License
/// along with this program; if not, write to the Free Software
/// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
module generator.stub.misc;

import std.array : join;
import logger = std.experimental.logger;

import clang.Cursor;

import translator.Type : TypeKind, translateType;

import generator.stub.types;

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
auto parmDeclToTypeName(Cursor cursor) {
    TypeName[] params;

    foreach (param; cursor.func.parameters) {
        auto type = translateType(param.type);
        params ~= TypeName(CppType(type.toString), CppVariable(param.spelling));
    }

    logger.trace(params);
    return params;
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
auto paramDeclToTypeKindVariable(Cursor cursor) {
    TypeKindVariable[] params;

    foreach (param; cursor.func.parameters) {
        auto type = translateType(param.type);
        params ~= TypeKindVariable(type, CppVariable(param.spelling));
    }

    logger.trace(params);
    return params;
}

string getPointerStars(const TypeKind v) pure @safe {
    import std.algorithm : count;

    char[] stars;
    stars.length = v.toString.count('*');
    stars[] = '*';

    return stars.idup;
}
