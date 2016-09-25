/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Extracted information of types.

TODO replace the fmt with a specialized formatting struct for the purpose
needed by TypeKind.  fmt is namely a typeless strict that do not encode the
assumed number or arguments when it is used.  In other words it do not contain
information regarding the number of '%s'.
*/
module cpptooling.analyzer.kind;

import std.conv : to;
import std.string : format;
import std.traits;
import std.typecons : Tuple, Nullable, Flag;
import logger = std.experimental.logger;

import cpptooling.data.symbol.types : USRType;

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

    this(T)(T info, USRType usr) if (!is(T == TypeKind)) {
        this.info = info;
        this.usr = usr;
    }

    this(T)(T info) if (!is(T == TypeKind)) {
        this(info, USRType(""));
    }

    this(TypeKind t) {
        this = t;
    }

    /** The type 'const int x[2][3]'
     */
    static struct ArrayInfo {
        /// int %s%s
        string fmt;
        /// [2, 3]
        ArrayInfoIndex[] indexes;
        /// usr for 'int'
        USRType element;
        /// Yes.isConst
        TypeAttr elementAttr;
    }

    /** The type 'extern int (*e_g)(int pa)'.
     *
     * attrs is only for the pointers, never the final pointee.
     * In the example shown about it would have length 2.
     *
     * TODO improve formatting with more separation, f.e return, ptr and args.
     * TODO add a USRType for the FuncPrototype.
     */
    static struct FuncPtrInfo {
        /// int (%s %s)(int pa)
        string fmt;
        /// USRs up the pointee
        USRType pointee;
        /// attributes of the pointer hierarchy. attr[0] is the right most ptr.
        TypeAttr[] attrs;
    }

    /** The type of a function signature, 'void foo(int)'.
     */
    static struct FuncSignatureInfo {
        /// void %s(int)
        string fmt;
        USRType return_;
        TypeAttr returnAttr;
        FuncInfoParam[] params;
    }

    /** The type of a function prototype, 'void foo(int)'.
     *
     * TODO consider changing the chain to be a FuncInfo referencing a FuncSignatureInfo.
     *
     * This coupled with FuncSignatureInfo having the USR of the signature
     * would mean that it would be possible to merge/detect/find all those
     * FuncInfo with the same symbol mangling/signature.
     *
     * Which is needed when doing cross-translation unit analyse to find
     * connections between "points of interest.
     *
     * It would also lower the amount of data in a FuncInfo.
     *
     */
    static struct FuncInfo {
        /// void %s(int)
        string fmt;
        USRType return_;
        TypeAttr returnAttr;
        FuncInfoParam[] params;
    }

    /** The type of a ctor prototype, 'Class::Class(int)'
     */
    static struct CtorInfo {
        /// %s(int)
        string fmt;
        /// Class
        string id;
        FuncInfoParam[] params;
    }

    /** The type of a dtor prototype, 'Class::~Class()'
     */
    static struct DtorInfo {
        /// ~%s()
        string fmt;
        /// identifier, in the example it would be 'Class'
        string id;
    }

    /** The type of a pointer (may be recursive), 'const int ** const x'
     *
     * attrs is only for the pointers, never the final pointee.
     * In the example shown about it would have length 2.
     */
    static struct PointerInfo {
        /// int%s %s
        string fmt;
        /// USRs up the pointee
        USRType pointee;
        /// attributes of the pointer hierarchy. attr[0] is the right most ptr.
        TypeAttr[] attrs;
    }

    /** Representation of a typedef, 'typedef int tx'
     *
     * canonicalType is the final resolved in a chain of typedef's.
     */
    static struct TypeRefInfo {
        /// tx %s
        string fmt;
        /// usr of the child type
        USRType typeRef;
        /// usr of the canonical type
        USRType canonicalRef;
    }

    /** Represent a primitive type.
     *
     * Similar to a $(D SimpleInfo) but used to distinguish primitive types
     * from "other" simple representations.
     *
     * The type 'int x' would be:
     */
    static struct PrimitiveInfo {
        /// int %s
        string fmt;
    }

    /** Textual representation of simple types.
     *
     * A simple type is one that do not need the features or distinction of the
     * other infos.
     *
     * The type 'const int x' would be:
     */
    static struct SimpleInfo {
        /// int %s
        string fmt;
    }

    /** The type 'const A'
     */
    static struct RecordInfo {
        /// A %s
        string fmt;
    }

    /// Formatting information needed to reproduce the type and identifier.
    static union InternalInfo {
        typeof(null) null_;
        PrimitiveInfo primitive;
        SimpleInfo simple;
        ArrayInfo array;

        FuncInfo func;
        FuncPtrInfo funcPtr;
        FuncSignatureInfo funcSignature;

        RecordInfo record;
        CtorInfo ctor;
        DtorInfo dtor;
        PointerInfo pointer;
        TypeRefInfo typeRef;
    }

    alias Info = TaggedAlgebraic!InternalInfo;

    Info info;
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
        case Kind.primitive:
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
        case Kind.funcSignature:
            assert(info.fmt.length > 0);
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

/// Attributes of a declaration of a type.
pure @safe nothrow @nogc struct TypeAttr {
    import std.typecons : Flag;

    Flag!"isConst" isConst;
    Flag!"isRef" isRef;
    Flag!"isPtr" isPtr;
    Flag!"isFuncPtr" isFuncPtr;
    Flag!"isArray" isArray;
    Flag!"isDefinition" isDefinition;
}

/** Returns: the USR for the referenced type.
 *
 * Params:
 *   LookupT = ?
 *   policy = only resolve those that matching the policy. If none are specified then resolve all.
 */
auto resolveTypeRef(LookupT, policy...)(TypeKind type, TypeAttr attr_, LookupT lookup) {
    import std.algorithm : among;
    import std.range : only, dropOne;
    import cpptooling.analyzer.type : TypeKindAttr;

    static if (policy.length > 0) {
        if (!type.info.kind.among(policy)) {
            return only(TypeKindAttr(type, attr_));
        }
    }

    auto rval = only(TypeKindAttr.init).dropOne;
    auto attr = attr_;
    auto found = typeof(lookup.kind(USRType.init)).init;

    final switch (type.info.kind) with (TypeKind.Info) {
    case Kind.array:
        attr = type.info.elementAttr;
        found = lookup.kind(type.info.element);
        break;
    case Kind.funcPtr:
        found = lookup.kind(type.info.pointee);
        break;
    case Kind.pointer:
        found = lookup.kind(type.info.pointee);
        break;
    case Kind.typeRef:
        found = lookup.kind(type.info.canonicalRef);
        break;
    case Kind.ctor:
    case Kind.dtor:
    case Kind.func:
    case Kind.funcSignature:
    case Kind.primitive:
    case Kind.record:
    case Kind.simple:
        rval = only(TypeKindAttr(type, attr));
        break;
    case Kind.null_:
        break;
    }

    foreach (item; found) {
        rval = only(TypeKindAttr(item.get, attr));
    }

    return rval;
}

/// DO NOT USE.
/// Internally used to get the fmt for debugging purpuse.
auto internalGetFmt(ref const TypeKind t) {
    final switch (t.info.kind) with (TypeKind.Info) {
    case Kind.primitive:
    case Kind.typeRef:
    case Kind.simple:
    case Kind.array:
    case Kind.func:
    case Kind.funcPtr:
    case Kind.funcSignature:
    case Kind.record:
    case Kind.pointer:
    case Kind.ctor:
    case Kind.dtor:
        return t.info.fmt;
    case Kind.null_:
        return "kind is @null@";
    }
}
