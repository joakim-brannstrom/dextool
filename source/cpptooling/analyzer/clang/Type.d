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
module translator.Type;

import std.conv : to;
import std.string : format;
import std.traits;
import logger = std.experimental.logger;

import deimos.clang.index : CXTypeKind;
import clang.Cursor : Cursor;
import clang.Type : Type;

public:

private void logType(ref Type type) {
    // dfmt off
    debug {
    logger.trace(format("%s|%s|%s|%s",
                        type.kind,
                        type.declaration,
                        type.isValid,
                        type.typeKindSpelling));
    }
    // dfmt on
}

/** Type information for a cursor.
 *
 * txt is type, qualifiers and storage class. For example const int *.
 */
pure @safe nothrow @nogc struct TypeKind {
    import cpptooling.utility.taggedalgebraic : TaggedAlgebraic;

    /** The type 'int x[2][3]'
     * elementType = int
     * indexes = [2][3]
     * fmt = %s %s%s
     */
    static struct ArrayInfo {
        string elementType;
        string indexes;
        string fmt;
    }

    /** The type 'extern int (*e_g)(int pa)'
     * fmt = int (*%s)(int pa)
     *
     * TODO improve formatting with more separation, f.e return, ptr and args.
     */
    static struct FuncPtrInfo {
        string fmt;
    }

    /** Textual representation of simple types.
     *
     * The type const int x would be:
     *
     * TODO add the following:
     * fmt = const int %s
     */
    static struct SimpleInfo {
        string fmt;
    }

    /// Formatting information needed to reproduce the type and identifier.
    static union InternalInfo {
        typeof(null) null_;
        SimpleInfo simple;
        ArrayInfo array;
        FuncPtrInfo funcPtr;
    }

    alias Info = TaggedAlgebraic!InternalInfo;
    Info info;

    bool isConst;
    bool isRef;
    bool isPointer;
    bool isFuncPtr;
    bool isArray;

    /** The full type with storage classes and operators.
     * Example
     * ---
     * const int&
     * ---
     */
    string toString() @property const {
        return txt;
    }

private:
    string txt;
}

private nothrow struct WrapTypeKind {
    this(Type type) {
        this.type = type;
        this.typeKind.txt = type.spelling;
        this.typeKind.info = TypeKind.SimpleInfo(this.typeKind.txt ~ " %s");

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

///TODO change thhe bools to using the Flag from typecons
TypeKind makeTypeKind(string txt, bool isConst, bool isRef, bool isPointer,
    bool isFuncPtr = false, bool isArray = false) pure @safe nothrow {
    TypeKind t;
    t.info = TypeKind.SimpleInfo(txt ~ " %s");
    t.txt = txt;
    t.isConst = isConst;
    t.isRef = isRef;
    t.isPointer = isPointer;
    t.isFuncPtr = isFuncPtr;
    t.isArray = isArray;

    return t;
}

/// Return a duplicate.
/// Side effect is that the the cursor is thrown away.
/// TODO investigate how this can be done withh opAssign and postblit.
TypeKind duplicate(T)(T t_in) pure @safe nothrow {
    TypeKind t = makeTypeKind(t_in.txt, t_in.isConst, t_in.isRef,
        t_in.isPointer, t_in.isFuncPtr, t_in.isArray);
    t.info = t_in.info;

    return t;
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
                result.typeKind.txt = translateUnexposed(type, false);
                break;
            case CXType_LValueReference:
                result = translateReference(type);
                break;
            default:
                result = translateDefault(type);
            }
        }
    }

    // dfmt off
    debug {
        logger.tracef("full:%s c:%s r:%s p:%s",
                      result.typeKind.toString,
                      result.typeKind.isConst,
                      result.typeKind.isRef,
                      result.typeKind.isPointer);
    }
    // dfmt on

    return result;
}

private:

WrapTypeKind translateDefault(Type type) {
    logType(type);

    auto result = WrapTypeKind(type);

    return result;
}

WrapTypeKind translateTypedef(Type type)
in {
    assert(type.kind == CXTypeKind.CXType_Typedef);
}
body {
    logType(type);

    static bool valueTypeIsConst(Type type) {
        auto pointee = type.pointeeType;

        while (pointee.kind == CXTypeKind.CXType_Pointer)
            pointee = pointee.pointeeType;

        return pointee.isConst;
    }

    auto result = WrapTypeKind(type);

    if (valueTypeIsConst(type)) {
        result.typeKind.isConst = true;
    }

    return result;
}

string translateUnexposed(Type type, bool rewriteIdToObject)
in {
    assert(type.kind == CXTypeKind.CXType_Unexposed);
}
body {
    auto declaration = type.declaration;

    if (declaration.isValid)
        return translateType(declaration.type).typeKind.txt;
    else
        return translateCursorType(type.kind);
}

WrapTypeKind translateConstantArray(Type type)
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
            info.elementType = translatedElement.typeKind.toString;
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

WrapTypeKind translateIncompleteArray(Type type)
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
            info.elementType = translatedElement.typeKind.toString;
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

WrapTypeKind translatePointer(Type type)
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

    auto result = WrapTypeKind(type);
    result.typeKind.isPointer = true;

    if (valueTypeIsConst(type)) {
        result.typeKind.isConst = true;
    }

    return result;
}

WrapTypeKind translateReference(Type type)
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

    auto result = WrapTypeKind(type);
    result.typeKind.isRef = true;

    if (valueTypeIsConst(type)) {
        result.typeKind.isConst = true;
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
    import clang.Token;

    //TODO investigate if it can be done simpler.
    //TODO spacing is funky
    static struct ConvToken {
        private string identifier;
        string spacing = "";
        string tok;

        this(string identifier) {
            this.identifier = identifier;
        }

        void convToken(long idx, Token t) {
            import deimos.clang.index : CXTokenKind;
            import std.algorithm : among;

            tok = t.spelling;

            switch (t.kind) with (CXTokenKind) {
            case CXToken_Keyword:
                if (idx == 0 && tok.among("extern")) {
                    tok = null;
                } else {
                    spacing = " ";
                }
                break;

            case CXToken_Punctuation:
                if (tok.among(";")) {
                    tok = null;
                }
                spacing = "";
                break;

            case CXToken_Identifier:
                spacing = " ";
                if (tok == identifier) {
                    tok = "%s";
                }
                break;
            default:
            }
        }
    }

    logger.trace("translateFunctionPointer");

    auto t = WrapTypeKind(type);
    auto func = type.pointeeType.func;
    auto toks = func.cursor.tokens;

    auto app = appender!string();
    auto c = ConvToken(type.cursor.spelling);
    foreach (index, value; toks.tokens.enumerate) {
        c.convToken(index, value);
        app.put(c.tok);
        app.put(c.spacing);
    }
    t.typeKind.info = TypeKind.FuncPtrInfo(app.data);
    t.typeKind.isFuncPtr = true;

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
