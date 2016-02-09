// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Extracted information of types.
*/
module cpptooling.analyzer.type;

import std.conv : to;
import std.string : format;
import std.traits;
import logger = std.experimental.logger;

/** Type represenation and information.
 *
 * txt is type, qualifiers and storage class. For example const int *.
 */
pure @safe nothrow @nogc struct TypeKind {
    import std.traits : isSomeString;
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

    auto txt() const {
        return txt_;
    }

    /** The full type with storage classes and operators.
     * Example
     * ---
     * const int&
     * ---
     */
    auto txt(string s) {
        if (txt_ is null)
            txt_ = s;
    }

    /// Crucial that the representation is correct.
    auto unsafeForceTxt(string s) {
        txt_ = s;
    }

private:
    string txt_;
}

///TODO change the bools to using the Flag from typecons
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

/** Return a duplicate.
 * Side effect is that the cursor is thrown away.
 * TODO investigate how this can be done with opAssign and postblit.
 */
TypeKind duplicate(T)(T t_in) pure @safe nothrow {
    TypeKind t = makeTypeKind(t_in.txt, t_in.isConst, t_in.isRef,
        t_in.isPointer, t_in.isFuncPtr, t_in.isArray);
    t.info = t_in.info;

    return t;
}

/// Combine type information with a identifier to produce a declaration.
auto toString(TypeKind t, string id) {
    import std.format : format;

    string txt;

    final switch (t.info.kind) with (TypeKind.Info) {
    case Kind.simple:
        txt = format(t.info.fmt, id);
        break;
    case Kind.array:
        txt = format(t.info.fmt, t.info.elementType, id, t.info.indexes);
        break;
    case Kind.funcPtr:
        txt = format(t.info.fmt, id);
        break;
    case Kind.null_:
        debug {
            logger.error("Type is null. Identifier ", id);
        }
        txt = id;
        break;
    }

    return txt;
}
