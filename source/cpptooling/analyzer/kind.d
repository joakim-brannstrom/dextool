// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Extracted information of types.
*/
module cpptooling.analyzer.kind;

import std.conv : to;
import std.string : format;
import std.traits;
import std.typecons : Tuple, Nullable, Flag;
import logger = std.experimental.logger;

import cpptooling.data.symbol.types : USRType;
import cpptooling.data.type : LocationTag;

alias ArrayInfoIndex = Nullable!long;
alias FuncInfoParam = Tuple!(USRType, "usr", TypeAttr, "attr", string, "id",
        Flag!"isVariadic", "isVariadic");

/// Convert an array of indexes to a string representation
string toRepr(const(ArrayInfoIndex[]) indexes) @safe pure {
    import std.algorithm : map, joiner;
    import std.conv : text;

    // dfmt off
    return indexes
        // a null is a dynamic index
        .map!(a => a.isNull ? "[]" : "[" ~ text(a.get) ~ "]")
        .joiner
        .text;
    // dfmt on
}

/** Type representation and information.
 */
pure @safe nothrow @nogc struct TypeKind {
    import std.traits : isSomeString;
    import cpptooling.utility.taggedalgebraic : TaggedAlgebraic;
    import std.typecons : Flag, Yes, No;

    this(TypeKind t) {
        this = t;
    }

    /** The type 'const int x[2][3]'
     *
     * fmt = int %s%s
     * indexes = [2, 3]
     * element = usr for 'int'
     * elementAttr = Yes.isConst
     */
    static struct ArrayInfo {
        string fmt;
        ArrayInfoIndex[] indexes;
        USRType element;
        TypeAttr elementAttr;
    }

    /** The type 'extern int (*e_g)(int pa)'
     *
     * attrs is only for the pointers, never the final pointee.
     * In the example shown about it would have length 2.
     *
     * attr[0] is the right most ptr.
     *
     * fmt = int (%s %s)(int pa)
     * pointee = USRs up the pointee
     * attrs = attributes of the pointer hierarchy
     *
     * TODO improve formatting with more separation, f.e return, ptr and args.
     * TODO add a USRType for the FuncPrototype.
     */
    static struct FuncPtrInfo {
        string fmt;
        USRType pointee;
        TypeAttr[] attrs;
    }

    /** The type of a function prototype, 'void foo(int)'
     * fmt = void %s(int)
     */
    static struct FuncInfo {
        string fmt;
        USRType return_;
        TypeAttr returnAttr;
        FuncInfoParam[] params;
    }

    /** The type of a ctor prototype, 'Class::Class(int)'
     *
     * fmt = %s(int)
     * id = Class
     */
    static struct CtorInfo {
        string fmt;
        string id;
        FuncInfoParam[] params;
    }

    /** The type of a dtor prototype, 'Class::~Class()'
     *
     * fmt = ~%s()
     * id = Class
     */
    static struct DtorInfo {
        string fmt;
        string id;
    }

    /** The type of a pointer (may be recursive), 'const int ** const x'
     *
     * attrs is only for the pointers, never the final pointee.
     * In the example shown about it would have length 2.
     *
     * attr[0] is the right most ptr.
     *
     * fmt = int%s %s
     * pointee = USRs up the pointee
     * attrs = attributes of the pointer hierarchy
     */
    static struct PointerInfo {
        string fmt;
        USRType pointee;
        TypeAttr[] attrs;
    }

    /** Representation of a typedef, 'typedef int tx'
     *
     * canonicalType is the final resolved in a chain of typedef's.
     *
     * fmt = tx %s
     * typeRef = usr of the child type
     * canonicalRef = usr of the canonical type
     */
    static struct TypeRefInfo {
        string fmt;
        USRType typeRef;
        USRType canonicalRef;
    }

    /** Textual representation of simple types.
     *
     * The type 'const int x' would be:
     *
     * fmt = int %s
     */
    static struct SimpleInfo {
        string fmt;
    }

    /** The type 'const A'
     *
     * fmt = A %s
     */
    static struct RecordInfo {
        string fmt;
    }

    /// Formatting information needed to reproduce the type and identifier.
    static union InternalInfo {
        typeof(null) null_;
        SimpleInfo simple;
        ArrayInfo array;
        FuncInfo func;
        FuncPtrInfo funcPtr;
        RecordInfo record;
        CtorInfo ctor;
        DtorInfo dtor;
        PointerInfo pointer;
        TypeRefInfo typeRef;
    }

    alias Info = TaggedAlgebraic!InternalInfo;

    Info info;
    LocationTag loc;
    USRType usr;

    invariant {
        final switch (this.info.kind) with (TypeKind.Info) {
        case Kind.ctor:
            // Assuming that a ctor or dtor must always have a id, otherwise
            // unusable
            goto case;
        case Kind.dtor:
            assert(info.id.length > 0);
            assert(info.fmt.length > 0);
            break;
        case Kind.record:
        case Kind.simple:
        case Kind.typeRef:
        case Kind.array:
        case Kind.func:
            assert(info.fmt.length > 0);
            break;
        case Kind.funcPtr:
            assert(info.fmt.length > 0);
            assert(info.attrs.length > 0);
            break;
        case Kind.pointer:
            assert(info.fmt.length > 0);
            assert(info.attrs.length > 0);
            break;
        case Kind.null_:
            break;
        }
    }
}

pure @safe nothrow @nogc struct TypeAttr {
    import std.typecons : Flag;

    Flag!"isConst" isConst;
    Flag!"isRef" isRef;
    Flag!"isPtr" isPtr;
    Flag!"isFuncPtr" isFuncPtr;
    Flag!"isArray" isArray;
    // TODO remove, redundant. Covered by the Algebraic type.
    Flag!"isRecord" isRecord;
    Flag!"isPrimitive" isPrimitive;
}

/// DO NOT USE.
/// Internally used to get the fmt for debugging purpuse.
auto internalGetFmt(ref const TypeKind t) {
    final switch (t.info.kind) with (TypeKind.Info) {
    case Kind.typeRef:
    case Kind.simple:
    case Kind.array:
    case Kind.func:
    case Kind.funcPtr:
    case Kind.record:
    case Kind.pointer:
    case Kind.ctor:
    case Kind.dtor:
        return t.info.fmt;
    case Kind.null_:
        return "kind is @null@";
    }
}
