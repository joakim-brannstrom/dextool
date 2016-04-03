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

/** Type representation and information.
 *
 * txt is type, qualifiers and storage class. For example const int *.
 */
pure @safe nothrow @nogc struct TypeKind {
    import std.traits : isSomeString;
    import cpptooling.utility.taggedalgebraic : TaggedAlgebraic;
    import std.typecons : Flag, Yes, No;

    static auto make(string txt) pure @safe nothrow {
        TypeKind t;
        t.info = TypeKind.SimpleInfo(txt ~ " %s", txt);
        t.txt = txt;

        return t;
    }

    /// Return a duplicate.
    static auto clone(inout TypeKind t_) pure @safe nothrow {
        TypeKind t = t_;
        return t;
    }

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

    /** The type of a function prototype, 'void foo(int)'
     * fmt = void %s(int)
     */
    static struct FuncInfo {
        string fmt;
    }

    /** Textual representation of simple types.
     *
     * The type 'const int x' would be:
     *
     * TODO add the following:
     * fmt = const int %s
     * type = int
     */
    static struct SimpleInfo {
        string fmt;
        string type;
    }

    /** The type 'const A*'
     *
     * fmt = const %s*
     * type = A
     */
    static struct RecordInfo {
        string fmt;
        string type;
    }

    /// Formatting information needed to reproduce the type and identifier.
    static union InternalInfo {
        typeof(null) null_;
        SimpleInfo simple;
        ArrayInfo array;
        FuncInfo func;
        FuncPtrInfo funcPtr;
        RecordInfo record;
    }

    alias Info = TaggedAlgebraic!InternalInfo;
    Info info;

    Flag!"isConst" isConst;
    Flag!"isRef" isRef;
    Flag!"isPtr" isPtr;
    Flag!"isFuncPtr" isFuncPtr;
    Flag!"isArray" isArray;
    Flag!"isRecord" isRecord;
    Flag!"isAnonymous" isAnonymous;

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

    invariant {
        // leading or trailing whitespace affects comparison.
        // therefor considered to be never be allowed.
        // it creates strange errors "far away", other parts of the program.
        // aka, no stripping shall ever be needed before comparing two type.
        final switch (this.info.kind) with (TypeKind.Info) {
        case Kind.record:
            assert(info.type.length == 0 || info.type[0] != ' ');
            break;
        case Kind.simple:
            assert(info.type.length == 0 || info.type[0] != ' ');
            break;
        case TypeKind.Info.Kind.func:
            break;
        case Kind.array:
            assert(info.elementType.length == 0 || info.elementType[0] != ' ');
            break;
        case Kind.funcPtr:
            break;
        case Kind.null_:
            break;
        }
    }

private:
    string txt_;
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
    case Kind.func:
        txt = format(t.info.fmt, id);
        break;
    case Kind.funcPtr:
        txt = format(t.info.fmt, id);
        break;
    case Kind.record:
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
