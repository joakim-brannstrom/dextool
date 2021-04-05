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
module cpptooling.data.kind;

import std.conv : to;
import std.string : format;
import std.traits;
import std.typecons : Nullable, Flag;
import logger = std.experimental.logger;

import my.sumtype;

import cpptooling.data.symbol.types : USRType;

version (unittest) {
    import unit_threaded : shouldEqual;
}

struct Void {
}

alias ArrayInfoIndex = Nullable!long;

struct FuncInfoParam {
    USRType usr;
    TypeAttr attr;
    string id;
    Flag!"isVariadic" isVariadic;
}

/// Convert an array of indexes to a string representation
string toRepr(ArrayInfoIndex[] indexes) @safe pure {
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

bool isIncompleteArray(ArrayInfoIndex[] indexes) @safe pure nothrow @nogc {
    foreach (index; indexes) {
        if (index.isNull)
            return true;
    }

    return false;
}

/** Type representation and information.
 */
struct TypeKind {
    import std.traits : isSomeString;
    import cpptooling.data.kind_type_format;

    this(T)(T info, USRType usr) @safe if (!is(T == TypeKind)) {
        this.info = info;
        this.usr = usr;
    }

    this(T)(T info) @safe if (!is(T == TypeKind)) {
        this(info, USRType.init);
    }

    invariant {
        info.match!((const TypeKind.CtorInfo t) => assert(t.id.length > 0),
                (const TypeKind.DtorInfo t) => assert(t.id.length > 0),
                (const TypeKind.FuncPtrInfo t) => assert(t.attrs.length > 0),
                (const TypeKind.PointerInfo t) => assert(t.attrs.length > 0), (_) {
        });
    }

    /// Formatting information needed to reproduce the type and identifier.
    alias Info = SumType!(ArrayInfo, CtorInfo, DtorInfo, FuncInfo, FuncPtrInfo,
            FuncSignatureInfo, PointerInfo, PrimitiveInfo, RecordInfo,
            SimpleInfo, TypeRefInfo, Void,);

    Info info;
    USRType usr;

pure @safe nothrow @nogc:

    /** The type 'const int x[2][3]'
     */
    static struct ArrayInfo {
        /// int %s%s
        ArrayFmt fmt;
        /// [2, 3]
        ArrayInfoIndex[] indexes;
        /// usr for 'int'
        USRType element;
    }

    /** The type 'extern int (*e_g)(int pa)'.
     *
     * attrs is only for the pointers, never the final pointee.
     * In the example shown about it would have length 1.
     *
     * TODO improve formatting with more separation, f.e return, ptr and args.
     * TODO add a USRType for the FuncPrototype.
     */
    static struct FuncPtrInfo {
        /// int (%s %s)(int pa)
        FuncPtrFmt fmt;
        /// USRs up the pointee
        USRType pointee;
        /// attributes of the pointer hierarchy. attr[0] is the right most ptr.
        TypeAttr[] attrs;
    }

    /** The type of a function signature, 'void foo(int)'.
     */
    static struct FuncSignatureInfo {
        /// void %s(int)
        FuncSignatureFmt fmt;
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
        FuncFmt fmt;
        USRType return_;
        TypeAttr returnAttr;
        FuncInfoParam[] params;
    }

    /** The type of a ctor prototype, 'Class::Class(int)'
     */
    static struct CtorInfo {
        /// %s(int)
        CtorFmt fmt;
        /// Class
        string id;
        FuncInfoParam[] params;
    }

    /** The type of a dtor prototype, 'Class::~Class()'
     */
    static struct DtorInfo {
        /// ~%s()
        DtorFmt fmt;
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
        PtrFmt fmt;
        /// USRs up the pointee
        USRType pointee;
        /// attributes of the pointer hierarchy. attr[0] is the left most ptr.
        TypeAttr[] attrs;
    }

    /** Representation of a typedef, 'typedef int tx'
     *
     * canonicalType is the final resolved in a chain of typedef's.
     */
    static struct TypeRefInfo {
        /// tx %s
        SimpleFmt fmt;
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
        SimpleFmt fmt;
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
        SimpleFmt fmt;
    }

    /** The type 'const A'
     */
    static struct RecordInfo {
        /// A %s
        SimpleFmt fmt;
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

    /// Returns: a string range of the attributes
    auto stringRange() {
        import std.range : chain, only;
        import std.algorithm : filter;

        // dfmt off
        return chain(only(isConst ? "const" : null),
              only(isRef ? "ref" : null),
              only(isPtr ? "ptr" : null),
              only(isFuncPtr ? "funcPtr" : null),
              only(isArray ? "array" : null))
            .filter!(a => a !is null);
        // dfmt on
    }

    ///
    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt = "%s") {
        import std.algorithm : joiner, copy;

        // dfmt off
        this.stringRange
            .joiner(";")
            .copy(w);
        // dfmt on
    }

    string toString() @safe pure {
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
    import cpptooling.data : TypeKindAttr, TypeKind, Void;

    auto rval = only(TypeKindAttr.init).dropOne;
    auto found = typeof(lookup.kind(USRType.init)).init;

    type.info.match!((TypeKind.ArrayInfo t) { found = lookup.kind(t.element); },
            (TypeKind.FuncPtrInfo t) { found = lookup.kind(t.pointee); }, (TypeKind.PointerInfo t) {
        found = lookup.kind(t.pointee);
    }, (TypeKind.TypeRefInfo t) { found = lookup.kind(t.canonicalRef); },
            restrictTo!(TypeKind.CtorInfo, TypeKind.DtorInfo,
                TypeKind.FuncInfo, TypeKind.FuncSignatureInfo,
                TypeKind.PrimitiveInfo, TypeKind.RecordInfo, TypeKind.SimpleInfo, (t) {
                rval = only(TypeKindAttr(type, attr));
            }), (Void t) {});

    foreach (item; found) {
        rval = only(TypeKindAttr(item.get, attr));
    }

    return rval;
}

/** Resolve the typeref type.
 *
 * TODO merge with resolvePointeeType. (It wasn't done as of this writing
 * because I'm not sure they will stay similare enough to allow a merge).
 *
 * Params:
 *   LookupT = a type supporting taking a USR and returning a TypeKind.
 *   type = the type to resolve
 *   lookup = see $(D LookupT)
 *
 * Returns: TypeKind of the canonical type.
 */
TypeKind resolveTypeRef(LookupT)(TypeKind type, LookupT lookup) {
    return type.info.match!((TypeKind.TypeRefInfo t) {
        foreach (a; lookup(t.canonicalRef)) {
            return a;
        }
        return type;
    }, _ => type);
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
    import cpptooling.data : TypeKindAttr, Void;

    auto rval = only(TypeKindAttr.init).dropOne;
    auto found = typeof(lookup.kind(USRType.init)).init;

    type.info.match!((TypeKind.ArrayInfo t) { found = lookup.kind(t.element); },
            (TypeKind.FuncPtrInfo t) { found = lookup.kind(t.pointee); }, (TypeKind.PointerInfo t) {
        found = lookup.kind(t.pointee);
    }, (Void t) {}, (_) { rval = only(TypeKindAttr(type, attr)); });

    foreach (item; found) {
        rval = only(TypeKindAttr(item.get, attr));
    }

    return rval;
}

// Test instantiation
@safe unittest {
    TypeKind tk;
}
