// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module clang.info;

import clang.Cursor;
import clang.Type;

import std.format : format;

/** Cursor isX represented as a string of letters
 *
 * a = isAttribute
 * A = isAnonymous
 * d = isDeclaration
 * D = isDefinition
 * e = isExpression
 * n = isEmpty aka isNull
 * p = isPreprocessing
 * r = isReference
 * s = isStatement
 * t = isTranslationUnit
 * u = isUnexposed
 * v = isVirtualBase
 * V = isValid
 */
string abilities(Cursor c) @trusted {
    string s = format("%s%s%s%s%s%s%s%s%s%s%s%s%s", c.isAttribute ? "a" : "",
            c.isAnonymous ? "A" : "", c.isDeclaration ? "d" : "", c.isDefinition
            ? "D" : "", c.isExpression ? "e" : "", c.isEmpty ? "n" : "",
            c.isPreprocessing ? "p" : "", c.isReference ? "r" : "", c.isStatement
            ? "s" : "", c.isTranslationUnit ? "t" : "", c.isUnexposed ? "u" : "",
            c.isVirtualBase ? "v" : "", c.isValid ? "V" : "",);

    return s;
}

/** FunctionCursor isX represented as a string of letters
 *
 * c = isConst
 * p = isPureVirtual
 * s = isStatic
 * V = isVirtual
 */
string abilities(FunctionCursor c) @trusted {
    string s = abilities(c.cursor);
    s ~= format(" %s%s%s%s", c.isConst ? "c" : "", c.isPureVirtual ? "p" : "",
            c.isStatic ? "s" : "", c.isVirtual ? "V" : "");

    return s;
}

/** EnumCursor isX represented as a string of letters
 *
 * s = isSigned
 * u = isUnderlyingTypeEnum
 */
string abilities(EnumCursor c) @trusted {
    string s = abilities(c.cursor);
    s ~= format(" %s%s", c.isSigned ? "s" : "", c.isUnderlyingTypeEnum ? "u" : "");

    return s;
}

/** Type isX represented as a string of letters
 *
 * a = isAnonymous
 * A = isArray
 * c = isConst
 * e = isEnum
 * E = isExposed
 * f = isFunctionType
 * F = isFunctionPointerType
 * p = isPOD
 * P = isPointer
 * r = isRestrict
 * t = isTypedef
 * v = isValid
 * V = isVolatile
 * w = isWideCharType
 */
string abilities(Type t) @trusted {
    string s = format("%s%s%s%s%s%s%s%s%s%s%s%s%s%s", t.isAnonymous ? "a" : "",
            t.isArray ? "A" : "", t.isConst ? "c" : "", t.isEnum ? "e" : "",
            t.isExposed ? "E" : "", t.isFunctionType ? "f" : "",
            t.isFunctionPointerType ? "F" : "", t.isPOD ? "p" : "", t.isPointer
            ? "P" : "", t.isRestrict ? "r" : "", t.isTypedef ? "t" : "", t.isValid
            ? "v" : "", t.isVolatile ? "V" : "", t.isWideCharType ? "w" : "",);

    return s;
}

/** FuncType isX represented as a string of letters
 *
 * v = isVariadic
 */
string abilities(ref FuncType t) @trusted {
    string s = format("%s %s", abilities(t.type), t.isVariadic ? "v" : "",);
    return s;
}
