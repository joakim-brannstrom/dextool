/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com).
///
/// Version: Initial created: Jan 30, 2012
/// Copyright (c) 2012 Jacob Carlborg. All rights reserved.
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
module cpptooling.analyzer.clang.type;

import std.conv : to;
import std.string : format;
import std.traits;
import logger = std.experimental.logger;

import deimos.clang.index : CXTypeKind;
import clang.Cursor : Cursor;
import clang.Type : Type;

public import cpptooling.analyzer.type;

void logType(ref Type type, string func = __FUNCTION__, uint line = __LINE__) {
    // dfmt off
    debug {
    logger.trace(format("%s:%s %s|%s|%s|%s",
                        func, line,
                        type.kind,
                        type.declaration,
                        type.isValid,
                        type.typeKindSpelling));
    }
    // dfmt on
}

nothrow struct WrapTypeKind {
    this(Type type) {
        this.type = type;
        this.typeKind.txt = type.spelling;

        this.typeKind.isConst = type.isConst;
        this.typeKind.isRef = type.declaration.isReference;
        this.typeKind.isPointer = (type.kind == CXTypeKind.CXType_Pointer);
        this.typeKind.isArray = type.isArray;
    }

    TypeKind unwrap() @safe nothrow @property {
        return this.typeKind;
    }

    Type type;
    TypeKind typeKind;
}

/** Translate a cursors type to a struct representation.
 * Params:
 *   type = a clang cursor to the type node
 * Returns: Struct of metadata about the type.
 */
WrapTypeKind translateType(Type type)
in {
    assert(type.isValid);
}
body {
    import clang.Cursor : cursor_abilities = abilities;
    import clang.Type : type_abilities = abilities;

    auto result = WrapTypeKind(type);

    debug {
        auto tmp_c = type.declaration;
        auto tmp_t = tmp_c.typedefUnderlyingType;
        // dfmt off
        logger.trace(format("%s %s %s %s c:%s t:%s",
                            type.spelling,
                            to!string(type.kind),
                            tmp_c.spelling,
                            type_abilities(tmp_t),
                            cursor_abilities(tmp_c),
                            type_abilities(type)));
        // dfmt on
    }

    with (CXTypeKind) {
        if (type.isWideCharType) {
            result.typeKind.txt = "wchar";
        } else if (type.kind == CXType_BlockPointer || type.isFunctionPointerType) {
            result = translateFunctionPointerType(type);
        } else {
            switch (type.kind) {
            case CXType_Pointer:
                result = translatePointer(type);
                break;
            case CXType_Typedef:
                result = translateTypedef(type);
                break;
            case CXType_ConstantArray:
                result = translateConstantArray(type);
                break;
            case CXType_IncompleteArray:
                result = translateIncompleteArray(type);
                break;
            case CXType_Unexposed:
                result = translateUnexposed(type);
                break;
            case CXType_LValueReference:
                result = translatePointer(type);
                break;
            case CXType_FunctionProto:
                result = translateFuncProto(type);
                break;
            default:
                result = translateDefault(type);
            }
        }
    }

    // dfmt off
    debug {
        logger.tracef("full:%s fmt:%s c:%s r:%s p:%s",
                      result.typeKind.txt,
                      result.typeKind.info.fmt,
                      result.typeKind.isConst,
                      result.typeKind.isRef,
                      result.typeKind.isPointer);

        tmp_c = result.type.declaration;
        tmp_t = tmp_c.typedefUnderlyingType;
        // dfmt off
        logger.trace(format("%s %s %s %s c:%s t:%s",
                            result.type.spelling,
                            to!string(result.type.kind),
                            tmp_c.spelling,
                            type_abilities(tmp_t),
                            cursor_abilities(tmp_c),
                            type_abilities(result.type)));
        // dfmt on
}
// dfmt on

return result;
}

private:

WrapTypeKind translateDefault(Type type) {
    logType(type);

    auto result = WrapTypeKind(type);
    result.typeKind.info = TypeKind.SimpleInfo(type.spelling ~ " %s");

    return result;
}

WrapTypeKind translateTypedef(Type type)
in {
    assert(type.kind == CXTypeKind.CXType_Typedef);
}
body {
    logger.trace("translateTypedef");
    logType(type);

    static bool valueTypeIsConst(Type type) {
        auto pointee = type.pointeeType;

        while (pointee.kind == CXTypeKind.CXType_Pointer)
            pointee = pointee.pointeeType;

        return pointee.isConst;
    }

    auto result = WrapTypeKind(type);
    result.typeKind.info = TypeKind.SimpleInfo(type.spelling ~ " %s");

    if (valueTypeIsConst(type)) {
        result.typeKind.isConst = true;
    }

    return result;
}

///TODO refactor the nested if's
auto translateUnexposed(Type type)
in {
    assert(type.kind == CXTypeKind.CXType_Unexposed);
}
body {
    logger.trace("translateUnexposed");
    logType(type);
    auto declaration = type.declaration;
    auto rval = WrapTypeKind(type);
    rval.typeKind.info = TypeKind.SimpleInfo(type.spelling ~ " %s");

    if (declaration.isValid) {
        rval = translateType(declaration.type);
    } else {
        auto canonical_type = type.canonicalType;
        if (canonical_type.isValid) {
            rval = translateType(canonical_type);
        } else {
            rval.typeKind.txt = translateCursorType(type.kind);
        }
    }

    return rval;
}

auto translateConstantArray(Type type)
in {
    assert(type.kind == CXTypeKind.CXType_ConstantArray);
}
body {
    import std.format : format;

    static TypeKind.ArrayInfo arrayInfo(Type t)
    in {
        assert(t.kind == CXTypeKind.CXType_ConstantArray);
    }
    body {
        TypeKind.ArrayInfo info;
        auto array = t.array;
        auto elementType = array.elementType;

        // peek at next element type to determine if base case is reached.
        switch (elementType.kind) {
        case CXTypeKind.CXType_ConstantArray:
            info = arrayInfo(elementType);
            info.indexes = format("[%d]%s", array.size, info.indexes);
            break;

        default:
            info.indexes = format("[%d]%s", array.size, info.indexes);
            auto translatedElement = translateType(elementType);
            assert(translatedElement.typeKind.info.kind == TypeKind.Info.Kind.simple);
            info.elementType = translatedElement.typeKind.txt;
            break;
        }

        return info;
    }

    logger.trace("translateConstantArray");
    auto result = WrapTypeKind(type);
    auto info = arrayInfo(type);
    info.fmt = "%s %s%s";
    result.typeKind.txt = format(info.fmt, info.elementType, "%s", info.indexes);
    result.typeKind.info = info;

    return result;
}

auto translateIncompleteArray(Type type)
in {
    assert(type.kind == CXTypeKind.CXType_IncompleteArray);
}
body {
    import std.format : format;

    static TypeKind.ArrayInfo arrayInfo(Type t)
    in {
        assert(t.kind == CXTypeKind.CXType_IncompleteArray);
    }
    body {
        TypeKind.ArrayInfo info;
        auto array = t.array;
        auto elementType = array.elementType;

        // peek at next element type to determine if base case is reached.
        switch (elementType.kind) {
        case CXTypeKind.CXType_IncompleteArray:
            info = arrayInfo(elementType);
            info.indexes = format("[]%s", info.indexes);
            break;

        default:
            info.indexes = format("[]%s", info.indexes);
            auto translatedElement = translateType(elementType);
            assert(translatedElement.typeKind.info.kind == TypeKind.Info.Kind.simple);
            info.elementType = translatedElement.typeKind.txt;
            break;
        }

        return info;
    }

    logger.trace("translateIncompleteArray");
    auto result = WrapTypeKind(type);
    auto info = arrayInfo(type);
    info.fmt = "%s %s%s";
    result.typeKind.txt = format(info.fmt, info.elementType, "%s", info.indexes);
    result.typeKind.info = info;

    return result;
}

auto visitPointeeType(WrapTypeKind t, string prefix) 
out (result) {
    assert(result.typeKind.info.kind == TypeKind.Info.Kind.simple);
}
body {
    logger.trace("visitPointeeType");
    logType(t.type);

    auto rval = translateType(t.type);

    TypeKind.SimpleInfo info;
    final switch (rval.typeKind.info.kind) {
    case TypeKind.Info.Kind.simple:
        info.fmt = rval.typeKind.toString(format("%s%s", prefix, "%s"));
        rval.typeKind.info = info;
        rval.typeKind.unsafeForceTxt(rval.typeKind.toString(""));
        break;
    case TypeKind.Info.Kind.array:
        info.fmt = rval.typeKind.toString(format("(%s%s)", prefix, "%s"));
        rval.typeKind.info = info;
        rval.typeKind.unsafeForceTxt(rval.typeKind.toString(""));
        break;
    case TypeKind.Info.Kind.funcPtr:
        //TODO a potential bug, implement this
        logger.errorf("ptr to func ptr is not implemented. '%s'", rval.typeKind.txt);
        break;
    case TypeKind.Info.Kind.null_:
        logger.errorf("info for type '%s' is null", t.typeKind.txt);
        break;
    }

    return rval;
}

auto translatePointer(Type type)
in {
    assert(type.kind == CXTypeKind.CXType_Pointer || type.kind == CXTypeKind.CXType_LValueReference);
}
body {
    string prefix;
    if (type.kind == CXTypeKind.CXType_Pointer) {
        prefix = "*";
    } else {
        prefix = "&";
    }

    logger.tracef("translatePointer (%s)", prefix);

    auto result = WrapTypeKind(type.pointeeType);
    result = visitPointeeType(result, prefix);

    result.typeKind.isPointer = type.kind == CXTypeKind.CXType_Pointer;
    result.typeKind.isRef = type.kind == CXTypeKind.CXType_LValueReference;
    result.typeKind.isConst = type.isConst;

    if (type.isConst) {
        TypeKind.SimpleInfo info;
        info.fmt = result.typeKind.toString("const %s");
        result.typeKind.info = info;
        result.typeKind.unsafeForceTxt(result.typeKind.toString(""));
    }

    return result;
}

WrapTypeKind translateFunctionPointerType(Type type)
in {
    assert(type.kind == CXTypeKind.CXType_BlockPointer || type.isFunctionPointerType);
}
body {
    import std.range : enumerate;
    import std.array : appender;

    logger.trace("translateFunctionPointer");

    auto t = WrapTypeKind(type.pointeeType);
    auto func = visitPointeeType(t, "");

    t.typeKind.isFuncPtr = true;
    t.typeKind.isConst = type.isConst;

    TypeKind.FuncPtrInfo info;
    if (type.isConst) {
        info.fmt = func.typeKind.toString("(*const %s)");
    } else {
        info.fmt = func.typeKind.toString("(*%s)");
    }
    t.typeKind.info = info;

    return t;
}

WrapTypeKind translateFuncProto(Type type)
in {
    assert(type.kind == CXTypeKind.CXType_FunctionProto);
}
body {
    import std.range : enumerate;
    import std.array : appender;
    import cpptooling.analyzer.clang.utility;

    logger.trace("translateFuncProto");

    auto t = WrapTypeKind(type);
    auto params = extractParams(type.cursor, type.func.isVariadic);
    auto return_t = translateType(type.func.resultType);

    TypeKind.SimpleInfo info;
    info.fmt = format("%s%s(%s)", return_t.typeKind.toString(""), "%s", params.joinParamNames());
    t.typeKind.info = info;
    t.typeKind.txt = t.typeKind.toString("");

    return t;
}

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
