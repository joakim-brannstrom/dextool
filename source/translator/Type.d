/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// Copyright: Copyright (c) 2012 Jacob Carlborg. All rights reserved.
/// Version: Initial created: Jan 30, 2012
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
module translator.Type;

private:

import std.array;
import std.conv;
import std.string;
import logger = std.experimental.logger;

import clang.c.index;
import clang.Cursor;
import clang.Token;
import clang.Type;

public:

/** Type information for a cursor.
 *
 * name is without any storage classes or operators. Example int.
 */
pure @safe nothrow struct TypeKind {
    string name;
    bool isConst;
    bool isRef;
    bool isPointer;

    /** The full type with storage classes and operators.
     * Example
     * ---
     * const int&
     * ---
     */
    @property string toString() const pure @safe nothrow {
        return full_name;
    }

private:
    string full_name;
    Type t;
}

/** Translate a cursors type to a struct representation.
 * Params:
 *   type = a clang cursor to the type node
 * Returns: Struct of metadata about the type.
 */
TypeKind translateType(Type type)
in {
    assert(type.isValid);
}
body {
    import std.algorithm;
    import std.array;

    TypeKind result = type.toProperty;
    result.t = type;
    result.full_name = type.spelling;

    auto tmp_c = type.declaration;
    auto tmp_t = tmp_c.typedefUnderlyingType;
    logger.trace(format("%s %s %s %s c:%s t:%s", type.spelling,
        to!string(type.kind), tmp_c.spelling, abilities(tmp_t), abilities(tmp_c), abilities(type)));

    with (CXTypeKind) {
        if (type.kind == CXType_BlockPointer || type.isFunctionPointerType)
            logger.error("Implement missing translation of function pointer");
        //    result = translateFunctionPointerType(type);

        if (type.isWideCharType)
            result.name = "wchar";
        else {
            switch (type.kind) {
            case CXType_Pointer:
                result = translatePointer(type);
                break;
            case CXType_Typedef:
                result = translateTypedef(type);
                break;

            case CXType_ConstantArray:
                result.name = translateConstantArray(type, false);
                break;
            case CXType_Unexposed:
                result.name = translateUnexposed(type, false);
                break;
            case CXType_LValueReference:
                result = translateReference(type);
                break;

            default:
                result = translateDefault(type);
            }
        }
    }
    logger.tracef("name:%s full:%s c:%s r:%s p:%s", result.name,
        result.toString, result.isConst, result.isRef, result.isPointer);

    return result;
}

private:

/** Extract properties from a Cursor for a Type like const, pointer, reference.
 * Params:
 *  cursor = A cursor that have a type property.
 */
TypeKind toProperty(Cursor cursor) {
    return cursor.type.toProperty;
}

/** Extract properties from a Type like const, pointer, reference.
 * Params:
 *  type = A cursor that have a type property.
 */
TypeKind toProperty(Type type) {
    TypeKind result;

    if (type.isConst) {
        result.isConst = true;
    }

    if (type.declaration.isReference) {
        result.isRef = true;
    }

    if (type.kind == CXTypeKind.CXType_Pointer) {
        result.isPointer = true;
    }

    return result;
}

TypeKind translateDefault(Type type) {
    logger.trace(format("%s|%s|%s|%s", type.kind, type.declaration,
        type.isValid, type.typeKindSpelling));

    TypeKind result = type.toProperty;
    result.t = type;
    result.full_name = type.spelling;
    result.name = translateCursorType(type.kind);

    return result;
}

TypeKind translateTypedef(Type type)
in {
    assert(type.kind == CXTypeKind.CXType_Typedef);
}
body {
    logger.trace(format("%s|%s|%s|%s", type.kind, type.declaration,
        type.isValid, type.typeKindSpelling));
    static bool valueTypeIsConst(Type type) {
        auto pointee = type.pointeeType;

        while (pointee.kind == CXTypeKind.CXType_Pointer)
            pointee = pointee.pointeeType;

        return pointee.isConst;
    }

    TypeKind result;

    result = type.toProperty;

    if (valueTypeIsConst(type)) {
        result.isConst = true;
    }

    result.name = type.declaration.spelling;
    if (result.name.length == 0) {
        result.name = type.spelling;
    }
    result.t = type;
    result.full_name = type.spelling;

    return result;
}

string translateUnexposed(Type type, bool rewriteIdToObject)
in {
    assert(type.kind == CXTypeKind.CXType_Unexposed);
}
body {
    auto declaration = type.declaration;

    if (declaration.isValid)
        return translateType(declaration.type).name;

    else
        return translateCursorType(type.kind);
}

string translateConstantArray(Type type, bool rewriteIdToObject)
in {
    assert(type.kind == CXTypeKind.CXType_ConstantArray);
}
body {
    auto array = type.array;
    auto elementType = translateType(array.elementType).name;

    return elementType ~ '[' ~ to!string(array.size) ~ ']';
}

TypeKind translatePointer(Type type)
in {
    assert(type.kind == CXTypeKind.CXType_Pointer);
}
body {
    logger.trace("translatePointer");
    static bool valueTypeIsConst(Type type) {
        auto pointee = type.pointeeType;

        while (pointee.kind == CXTypeKind.CXType_Pointer)
            pointee = pointee.pointeeType;

        return pointee.isConst;
    }

    TypeKind result = type.toProperty;
    result.isPointer = true;

    if (valueTypeIsConst(type)) {
        result.isConst = true;
    }

    auto tmp = translateType(type.pointeeType);
    result.name = tmp.t.declaration.spelling;
    if (result.name.length == 0) {
        result.name = tmp.name;
    }
    result.t = type;
    result.full_name = type.spelling;

    return result;
}

TypeKind translateReference(Type type)
in {
    assert(type.kind == CXTypeKind.CXType_LValueReference);
}
body {
    logger.trace("translateReference");
    static bool valueTypeIsConst(Type type) {
        auto pointee = type.pointeeType;

        while (pointee.kind == CXTypeKind.CXType_Pointer)
            pointee = pointee.pointeeType;

        return pointee.isConst;
    }

    TypeKind result = type.toProperty;
    result.isRef = true;

    if (valueTypeIsConst(type)) {
        result.isConst = true;
    }

    auto tmp = translateType(type.pointeeType);
    result.name = tmp.t.declaration.spelling;
    if (result.name.length == 0) {
        result.name = tmp.name;
    }
    result.t = type;
    result.full_name = type.spelling;

    return result;
}

//string translateFunctionPointerType (Type type)
//    in
//{
//    assert(type.kind == CXTypeKind.CXType_BlockPointer || type.isFunctionPointerType);
//}
//body
//{
//    auto func = type.pointeeType.func;
//
//    Parameter[] params;
//    params.reserve(func.arguments.length);
//
//    foreach (type ; func.arguments)
//        params ~= Parameter(translateType(type));
//
//    auto resultType = translateType(func.resultType);
//
//    return translateFunction(resultType, "function", params, func.isVariadic, new String);
//}

string translateCursorType(CXTypeKind kind) {
    with (CXTypeKind) switch (kind) {
    case CXType_Invalid:
        return "<unimplemented>";
    case CXType_Unexposed:
        return "<unimplemented>";
    case CXType_Void:
        return "void";
    case CXType_Bool:
        return "bool";
    case CXType_Char_U:
        return "unsigned char";
    case CXType_UChar:
        return "unsigned char";
    case CXType_Char16:
        return "<unimplemented>";
    case CXType_Char32:
        return "<unimplemented>";
    case CXType_UShort:
        return "unsigned short";
    case CXType_UInt:
        return "unsigned int";

    case CXType_ULong:
        return "unsigned long";

    case CXType_ULongLong:
        return "unsigned long long";
    case CXType_UInt128:
        return "<unimplemented>";
    case CXType_Char_S:
        return "char";
    case CXType_SChar:
        return "char";
    case CXType_WChar:
        return "wchar";
    case CXType_Short:
        return "short";
    case CXType_Int:
        return "int";

    case CXType_Long:
        return "long";

    case CXType_LongLong:
        return "long long";
    case CXType_Int128:
        return "<unimplemented>";
    case CXType_Float:
        return "float";
    case CXType_Double:
        return "double";
    case CXType_LongDouble:
        return "long double";
    case CXType_NullPtr:
        return "null";
    case CXType_Overload:
        return "<unimplemented>";
    case CXType_Dependent:
        return "<unimplemented>";
        //case CXType_ObjCId: return rewriteIdToObjcObject ? "ObjcObject" : "id";
    case CXType_ObjCId:
        return "ObjcObject";
    case CXType_ObjCClass:
        return "Class";
    case CXType_ObjCSel:
        return "SEL";

    case CXType_Complex:
    case CXType_Pointer:
    case CXType_BlockPointer:
    case CXType_LValueReference:
    case CXType_RValueReference:
    case CXType_Record:
    case CXType_Enum:
    case CXType_Typedef:
    case CXType_FunctionNoProto:
    case CXType_FunctionProto:
    case CXType_Vector:
    case CXType_IncompleteArray:
    case CXType_VariableArray:
    case CXType_DependentSizedArray:
    case CXType_MemberPointer:
        return "<unimplemented>";

    default:
        assert(0, "Unhandled type kind " ~ to!string(kind));
    }
}
