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
import std.typecons : Nullable, Flag;
import logger = std.experimental.logger;

import cpptooling.data.symbol.types : USRType;

version (unittest) {
    import unit_threaded : Name, shouldEqual;
} else {
    private struct Name {
        string name_;
    }
}

alias ArrayInfoIndex = Nullable!long;
struct FuncInfoParam {
    USRType usr;
    TypeAttr attr;
    string id;
    Flag!"isVariadic" isVariadic;
}

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
struct TypeKind {
    import std.traits : isSomeString;
    import cpptooling.utility.taggedalgebraic : TaggedAlgebraic;

    this(T)(T info, USRType usr) @safe if (!is(T == TypeKind)) {
        this.info = info;
        this.usr = usr;
    }

    this(T)(T info) @safe if (!is(T == TypeKind)) {
        this(info, USRType(""));
    }

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

    /// Formatting information needed to reproduce the type and identifier.
    static @safe pure nothrow @nogc union InternalInfo {
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

pure @safe nothrow @nogc:

    /** The type 'const int x[2][3]'
     */
    static struct ArrayInfo {
        /// int %s%s
        string fmt;
        /// [2, 3]
        ArrayInfoIndex[] indexes;
        /// usr for 'int'
        USRType element;
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
}

/// Attributes for a type.
@safe @nogc struct TypeAttr {
    import std.typecons : Flag;
    import std.format : FormatSpec;

    Flag!"isConst" isConst;
    Flag!"isRef" isRef;
    Flag!"isPtr" isPtr;
    Flag!"isFuncPtr" isFuncPtr;
    Flag!"isArray" isArray;
    Flag!"isDefinition" isDefinition;

    ///
    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt = "%s") const {
        import std.range : chain, only;
        import std.algorithm : filter, joiner, copy;

        // dfmt off
        chain(only(isConst ? "const" : null),
              only(isRef ? "ref" : null),
              only(isPtr ? "ptr" : null),
              only(isFuncPtr ? "funcPtr" : null),
              only(isArray ? "array" : null))
            .filter!(a => a !is null)
            .joiner(";")
            .copy(w);
        // dfmt on
    }

    string toString() @safe pure const {
        import std.exception : assumeUnique;
        import std.format : FormatSpec;

        char[] buf;
        buf.reserve(100);
        auto fmt = FormatSpec!char("%s");
        toString((const(char)[] s) { buf ~= s; }, fmt);
        auto trustedUnique(T)(T t) @trusted {
            return assumeUnique(t);
        }

        return trustedUnique(buf);
    }
}

/** Resolve the canonical type.
 *
 * TODO merge with resolvePointeeType. (It wasn't done as of this writing
 * because I'm not sure they will stay similare enough to allow a merge).
 *
 * TODO I think that the resuilt from array/funcPtr/pointee should be checked
 * if they are a typedef. May be a bug that complicates the result at other
 * places.
 *
 * Params:
 *   LookupT = a type supporting the method "kind" taking a USR and returning a
 *             TypeKind.
 *   type = the type to resolve
 *   attr_ = attributes for the type, depending on the result from the lookup
 *           either this attributes are used or those from the lookup
 *   lookup = see $(D LookupT)
 *
 * Returns: TypeKindAttr of the canonical type.
 */
auto resolveCanonicalType(LookupT)(TypeKind type, TypeAttr attr, LookupT lookup)
        if (__traits(hasMember, LookupT, "kind")) {
    import std.algorithm : among;
    import std.range : only, dropOne;
    import cpptooling.analyzer.type : TypeKindAttr;

    auto rval = only(TypeKindAttr.init).dropOne;
    auto found = typeof(lookup.kind(USRType.init)).init;

    final switch (type.info.kind) with (TypeKind.Info) {
    case Kind.array:
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

/** Resolve the pointe type.
 *
 * Params:
 *   LookupT = a type supporting the method "kind" taking a USR as parameter,
 *      returning the result as a TypeKind wrapped in a range.
 *   type = the type to resolve
 *   attr_ = attributes for the type, depending on the result from the lookup
 *      either this attributes are used or those from the lookup
 *   lookup = see $(D LookupT)
 *
 * Returns: TypeKindAttr of the pointee type.
 */
auto resolvePointeeType(LookupT)(TypeKind type, TypeAttr attr, LookupT lookup)
        if (__traits(hasMember, LookupT, "kind")) {
    import std.algorithm : among;
    import std.range : only, dropOne;
    import cpptooling.analyzer.type : TypeKindAttr;

    auto rval = only(TypeKindAttr.init).dropOne;
    auto found = typeof(lookup.kind(USRType.init)).init;

    final switch (type.info.kind) with (TypeKind.Info) {
    case Kind.array:
        found = lookup.kind(type.info.element);
        break;
    case Kind.funcPtr:
        found = lookup.kind(type.info.pointee);
        break;
    case Kind.pointer:
        found = lookup.kind(type.info.pointee);
        break;
    case Kind.typeRef:
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

// Test instantiation
@safe unittest {
    TypeKind tk;
}
