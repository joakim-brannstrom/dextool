// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Version: Initial created: Jan 30, 2012
Copyright (c) 2012 Jacob Carlborg. All rights reserved.
*/
module cpptooling.analyzer.clang.type;

import std.conv : to;
import std.string : format;
import std.traits;
import std.typecons : Flag, Yes, No;
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

        this.typeKind.isConst = cast(Flag!"isConst") type.isConst;
        this.typeKind.isRef = cast(Flag!"isRef") type.declaration.isReference;
        this.typeKind.isPtr = cast(Flag!"isPtr")(type.kind == CXTypeKind.CXType_Pointer);
        this.typeKind.isArray = cast(Flag!"isArray") type.isArray;
        this.typeKind.isRecord = cast(Flag!"isRecord")(type.kind == CXTypeKind.CXType_Record);
        this.typeKind.isAnonymous = cast(Flag!"isAnonymous")(type.isAnonymous);
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
out (result) {
    switch (result.typeKind.info.kind) with (TypeKind.Info.Kind) {
    case simple:
        goto case;
    case record:
        assert(result.typeKind.info.type != "");
        break;
    case null_:
        assert(false);
        break;
    default:
        break;
    }
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
        if (type.kind == CXType_BlockPointer || type.isFunctionPointerType) {
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
            case CXType_Record:
                result = translateRecord(type);
                break;
            default:
                result = translateDefault(type);
            }
        }
    }

    debug {
        // dfmt off
        logger.tracef("full:%s fmt:%s c:%s r:%s p:%s rr:%s a:%s",
                      result.typeKind.txt,
                      result.typeKind.info.kind != TypeKind.Info.Kind.null_ ? result.typeKind.info.fmt : "",
                      result.typeKind.isConst,
                      result.typeKind.isRef,
                      result.typeKind.isPtr,
                      result.typeKind.isRecord,
                      result.typeKind.isAnonymous);
        // dfmt on

        switch (result.typeKind.info.kind) with (TypeKind.Info.Kind) {
        case simple:
            goto case;
        case record:
            logger.trace("  type:", result.typeKind.info.type);
            break;
        default:
            break;
        }

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

    return result;
}

private:

WrapTypeKind translateDefault(Type type) {
    logType(type);

    auto result = WrapTypeKind(type);
    result.typeKind.info = TypeKind.SimpleInfo(type.spelling ~ " %s", type.spelling);

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
    result.typeKind.info = TypeKind.SimpleInfo(type.spelling ~ " %s", type.spelling);

    if (valueTypeIsConst(type)) {
        result.typeKind.isConst = Yes.isConst;
    }

    return result;
}

/** Try and find the type via declaration or canonical type.
 *
 * It is possible to get stuck in an infinite loop of unexposed, passing
 * along an incr index to detect and break the recursion.
 *
 * TODO refactor the nested if's
 * TODO investigate if the declaration branch should check if rec_depth == 0,
 * would force a check on canonical. Then when rec_depth == 2, "give up".
 *
 * Params:
 *  type = type to expose
 *  rec_depth = nr of recursions
 *
 * Return: The exposed type, if found. Otherwise raw spelling.
 */
WrapTypeKind translateUnexposed(Type type, uint rec_depth = 0)
in {
    assert(type.kind == CXTypeKind.CXType_Unexposed);
}
out (result) {
    switch (result.typeKind.info.kind) with (TypeKind.Info.Kind) {
    case simple:
        goto case;
    case record:
        assert(result.typeKind.info.type != "");
        break;
    case null_:
        assert(false);
        break;
    default:
        break;
    }
}
body {
    logger.trace("translateUnexposed");
    logType(type);
    auto declaration = type.declaration;
    auto rval = WrapTypeKind(type);

    rval.typeKind.info = TypeKind.SimpleInfo(type.spelling ~ " %s", type.spelling);

    if (rec_depth == 2) {
        rval.typeKind.txt = type.spelling;
        logger.error("Giving up, unable to determine the underlying type: ", rval.typeKind.txt);
    } else if (declaration.isValid && declaration.type.isValid) {
        if (declaration.type.kind == CXTypeKind.CXType_Unexposed) {
            rval = translateUnexposed(declaration.type, rec_depth + 1);
        } else {
            rval = translateType(declaration.type);
        }
    } else {
        auto canonical_type = type.canonicalType;

        if (canonical_type.kind == CXTypeKind.CXType_Unexposed) {
            rval = translateUnexposed(canonical_type, rec_depth + 1);
        } else if (canonical_type.isValid) {
            rval = translateType(canonical_type);
        } else {
            // I don't think this case ever happens
            rval.typeKind.txt = translateCursorType(type.kind);
        }
    }

    if (type.isConst) {
        rval.typeKind.isConst = cast(Flag!"isConst") type.isConst;

        // unsure if this is a stable way of solving the const of unexposed
        // types. But seems to be good enough.
        final switch (rval.typeKind.info.kind) {
        case TypeKind.Info.Kind.func:
            logger.errorf("a func (not ptr) can't be const: ", rval.typeKind.txt);
            break;
        case TypeKind.Info.Kind.record:
            TypeKind.RecordInfo info;
            info.fmt = "const " ~ rval.typeKind.info.fmt;
            info.type = rval.typeKind.toString("");
            rval.typeKind.info = info;
            rval.typeKind.unsafeForceTxt(rval.typeKind.toString(""));
            logger.trace(info.type);
            break;
        case TypeKind.Info.Kind.simple:
            TypeKind.SimpleInfo info;
            //TODO this isn't correct when analyzing a template, const should
            //then be inside the template for each template parameter it occur
            //on.
            info.fmt = "const " ~ rval.typeKind.info.fmt;
            info.type = rval.typeKind.toString("");
            rval.typeKind.info = info;
            rval.typeKind.unsafeForceTxt(rval.typeKind.toString(""));
            logger.trace(info.type);
            break;
        case TypeKind.Info.Kind.array:
            goto case;
        case TypeKind.Info.Kind.funcPtr:
            logger.errorf("info for type '%s' is not implemented", rval.typeKind.txt);
            break;
        case TypeKind.Info.Kind.null_:
            logger.errorf("info for type '%s' is null", rval.typeKind.txt);
            break;
        }
    }

    import std.algorithm : canFind;

    if (rval.typeKind.txt.canFind("(anonymous ")) {
        //TODO handle this case in the future
        // ugly as hell.... how to determine this from the AST?
        logger.error("Anonymous type: ", rval.typeKind.txt);
        rval.typeKind.isAnonymous = Yes.isAnonymous;
    }

    return rval;
}

auto translateConstantArray(Type type)
in {
    assert(type.kind == CXTypeKind.CXType_ConstantArray);
}
out (result) {
    assert(result.typeKind.info.kind == TypeKind.Info.Kind.array);
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

            assert(translatedElement.typeKind.info.kind == TypeKind.Info.Kind.simple
                    || translatedElement.typeKind.info.kind == TypeKind.Info.Kind.record);

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

            assert(translatedElement.typeKind.info.kind == TypeKind.Info.Kind.simple
                    || translatedElement.typeKind.info.kind == TypeKind.Info.Kind.record);

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

    //TODO refactor, this is ugly repetative code
    final switch (rval.typeKind.info.kind) with (TypeKind.Info.Kind) {
    case func:
        info.fmt = rval.typeKind.toString(format("%s%s", prefix, "%s"));
        // ugly hack to get some type of pure type information
        info.type = rval.typeKind.toString("");
        rval.typeKind.info = info;
        rval.typeKind.unsafeForceTxt(rval.typeKind.toString(""));
        break;
    case record:
        info.fmt = rval.typeKind.toString(format("%s%s", prefix, "%s"));
        info.type = rval.typeKind.info.type;
        rval.typeKind.info = info;
        rval.typeKind.unsafeForceTxt(rval.typeKind.toString(""));
        break;
    case simple:
        info.fmt = rval.typeKind.toString(format("%s%s", prefix, "%s"));
        info.type = rval.typeKind.info.type;
        rval.typeKind.info = info;
        rval.typeKind.unsafeForceTxt(rval.typeKind.toString(""));
        break;
    case array:
        info.fmt = rval.typeKind.toString(format("(%s%s)", prefix, "%s"));
        info.type = rval.typeKind.toString("");
        rval.typeKind.info = info;
        rval.typeKind.unsafeForceTxt(rval.typeKind.toString(""));
        break;
    case funcPtr:
        //TODO a potential bug, implement this
        logger.errorf("ptr to func ptr is not implemented. '%s'", rval.typeKind.txt);
        break;
    case null_:
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

    result.typeKind.isPtr = cast(Flag!"isPtr")(type.kind == CXTypeKind.CXType_Pointer);
    result.typeKind.isRef = cast(Flag!"isRef")(type.kind == CXTypeKind.CXType_LValueReference);
    result.typeKind.isConst = cast(Flag!"isConst") type.isConst;

    if (type.isConst) {
        //TODO investigate if the other types shouldn't be handled differently
        // from simple. Among others to be able to keep the kind.
        final switch (result.typeKind.info.kind) with (TypeKind.Info.Kind) {
        case func:
            goto case;
        case record:
            goto case;
        case funcPtr:
            goto case;
        case array:
            goto case;
        case simple:
            auto info = TypeKind.SimpleInfo(result.typeKind.toString("const %s"),
                    result.typeKind.info.type);
            result.typeKind.info = info;
            result.typeKind.unsafeForceTxt(result.typeKind.toString(""));
            break;
        case null_:
            logger.errorf("info for type '%s' is null", result.typeKind.txt);
            break;
        }
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

    t.typeKind.isFuncPtr = Yes.isFuncPtr;
    t.typeKind.isConst = cast(Flag!"isConst") type.isConst;

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

    TypeKind.FuncInfo info;
    info.fmt = format("%s%s(%s)", return_t.typeKind.toString(""), "%s", params.joinParamNames());
    t.typeKind.info = info;
    t.typeKind.txt = t.typeKind.toString("");

    return t;
}

WrapTypeKind translateRecord(Type type)
in {
    assert(type.kind == CXTypeKind.CXType_Record);
}
body {
    logger.trace("translateRecord");

    auto t = translateDefault(type);
    TypeKind.RecordInfo info;
    info.fmt = t.typeKind.info.fmt;
    info.type = t.typeKind.info.type;

    if (t.typeKind.isConst) {
        // ugly hack to strip prefix const
        info.type = info.type[6 .. $];
    }

    //TODO remove this trace in the future
    logger.trace(type.spelling, ":", type.canonicalType.spelling);

    t.typeKind.info = info;
    t.typeKind.isRecord = Yes.isRecord;

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
