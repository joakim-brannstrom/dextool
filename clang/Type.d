/**
 * Copyright: Copyright (c) 2011 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg, Joakim Brännström (joakim.brannstrom dottli gmx.com)
 * Version: 1.1
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 * History:
 *  1.0 initial release. 2012-01-29 $(BR)
 *    Jacob Carlborg
 *
 *  1.1 additional features missing compared to cindex.py. 2015-03-07 $(BR)
 *    Joakim Brännström
 */
module clang.Type;

import clang.c.Index;

import clang.Cursor;
import clang.Util;

struct Type {
    mixin CX;

    Cursor cursor;

    this(Type type) {
        cursor = type.cursor;
        cx = type.cx;
    }

    this(Cursor c, CXType cx) {
        cursor = c;
        this.cx = cx;
    }

    /** Pretty-print the underlying type using the rules of the language of the
     * translation unit from which it came.
     *
     * If the type is invalid, an empty string is returned.
     */
    @property string spelling() {
        auto r = toD(clang_getTypeSpelling(cx));
        return r;
    }

    @property string typeKindSpelling() {
        auto r = toD(clang_getTypeKindSpelling(cx.kind));
        return r;
    }

    /** Return the canonical type for a CXType.
     *
     * Clang's type system explicitly models aliases and all the ways a
     * specific type can be represented.  The canonical type is the underlying
     * type with all the "sugar" removed.  For example, if 'T' is a typedef for
     * 'int', the canonical type for 'T' would be 'int'.
     */
    @property Type canonicalType() {
        auto r = clang_getCanonicalType(cx);
        return Type(cursor, r);
    }

    /// For pointer types, returns the type of the pointee.
    @property Type pointeeType() {
        auto r = clang_getPointeeType(cx);
        //TODO investigate if it is buggy behaviour to reuse THIS cursor.
        // Shouldn't it be the pointee types cursor
        return Type(cursor, r);
    }

    /// Return: the cursor for the declaration of the given type.
    @property Cursor declaration() @trusted {
        auto r = clang_getTypeDeclaration(cx);
        return Cursor(r);
    }

    @property FuncType func() {
        return FuncType(this);
    }

    @property ArrayType array() {
        return ArrayType(this);
    }

    /** Determine whether two CXTypes represent the same type.
     *
     * Returns:non-zero if the CXTypes represent the same type and zero otherwise.
     */
    equals_t opEquals(const ref Type type_) const {
        return clang_equalTypes(cast(CXType) type_.cx, cast(CXType) cx) != 0;
    }

    @property bool isTypedef() const {
        return kind == CXTypeKind.typedef_;
    }

    @property bool isEnum() const {
        return kind == CXTypeKind.enum_;
    }

    @property bool isValid() const {
        return kind != CXTypeKind.invalid;
    }

    @property bool isFunctionType() {
        return canonicalType.kind == CXTypeKind.functionProto;
    }

    @property bool isFunctionPointerType() {
        return kind == CXTypeKind.pointer && pointeeType.isFunctionType;
    }

    @property bool isObjCIdType() {
        return isTypedef && canonicalType.kind == CXTypeKind.objCObjectPointer && spelling == "id";
    }

    @property bool isObjCClassType() {
        return isTypedef && canonicalType.kind == CXTypeKind.objCObjectPointer && spelling == "Class";
    }

    @property bool isObjCSelType() {
        if (isTypedef) {
            auto c = canonicalType;
            return c.kind == CXTypeKind.pointer && c.pointeeType.kind == CXTypeKind.objCSel;
        } else
            return false;
    }

    @property bool isObjCBuiltinType() {
        return isObjCIdType || isObjCClassType || isObjCSelType;
    }

    @property bool isWideCharType() const {
        return kind == CXTypeKind.wChar;
    }

    /** Determine whether a CXType has the "const" qualifier set, without
     * looking through aliases that may have added "const" at a different
     * level.
     */
    @property bool isConst() {
        return clang_isConstQualifiedType(cx) == 1;
    }

    @property bool isExposed() const {
        return kind != CXTypeKind.unexposed;
    }

    @property bool isArray() const {
        return kind == CXTypeKind.constantArray || kind == CXTypeKind.incompleteArray;
    }

    @property bool isAnonymous() {
        return spelling.length == 0;
    }

    /** Determine whether a CXType has the "volatile" qualifier set, without
     * looking through aliases that may have added "volatile" at a different
     * level.
     */
    @property bool isVolatile() {
        return clang_isVolatileQualifiedType(cx) == 1;
    }

    /** Determine whether a CXType has the "restrict" qualifier set, without
     * looking through aliases that may have added "restrict" at a different
     * level.
     */
    @property bool isRestrict() {
        return clang_isRestrictQualifiedType(cx) == 1;
    }

    /// Return: if the CXType is a POD (plain old data)
    @property bool isPOD() {
        return clang_isPODType(cx) == 1;
    }

    @property bool isPointer() {
        import std.algorithm : among;

        with (CXTypeKind) {
            return kind.among(pointer, blockPointer, memberPointer,
                    lValueReference, rValueReference) != 0;
        }
    }

}

struct FuncType {
    Type type;
    alias type this;

    @property Type resultType() {
        auto r = clang_getResultType(type.cx);
        return Type(type.cursor, r);
    }

    @property Arguments arguments() {
        return Arguments(this);
    }

    @property bool isVariadic() {
        return clang_isFunctionTypeVariadic(type.cx) == 1;
    }
}

struct ArrayType {
    Type type;
    alias type this;

    this(Type type)
    in {
        assert(type.isArray);
    }
    body {
        this.type = type;
    }

    /** Return the element type of an array, complex, or vector type.
     *
     * If a type is passed in that is not an array, complex, or vector type,
     * an invalid type is returned.
     */
    @property Type elementType() {
        auto r = clang_getElementType(cx);
        return Type(type.cursor, r);
    }

    /** Return: Number of dimensions the array consist of */
    @property size_t numDimensions() {
        size_t result = 1;
        auto subtype = elementType();

        while (subtype.isArray) {
            ++result;
            subtype = subtype.array.elementType();
        }

        return result;
    }

    /** Return the number of elements of an array or vector type.
     *
     * If a type is passed in that is not an array or vector type,
     * -1 is returned.
     */
    @property auto numElements() {
        return clang_getNumElements(cx);
    }

    /** Return the element type of an array type.
     *
     * If a non-array type is passed in, an invalid type is returned.
     */
    @property Type elementArrayType() {
        auto r = clang_getArrayElementType(cx);
        return Type(type.cursor, r);
    }

    @property long size() {
        return clang_getArraySize(cx);
    }
}

struct Arguments {
    FuncType type;

    @property uint length() {
        return clang_getNumArgTypes(type.type.cx);
    }

    Type opIndex(uint i) {
        auto r = clang_getArgType(type.type.cx, i);
        return Type(type.cursor, r);
    }

    int opApply(int delegate(ref Type) dg) {
        foreach (i; 0 .. length) {
            auto type = this[i];

            if (auto result = dg(type))
                return result;
        }

        return 0;
    }
}

@property bool isUnsigned(CXTypeKind kind) {
    switch (kind) with (CXTypeKind) {
    case charU:
        return true;
    case uChar:
        return true;
    case uShort:
        return true;
    case uInt:
        return true;
    case uLong:
        return true;
    case uLongLong:
        return true;
    case uInt128:
        return true;

    default:
        return false;
    }
}
