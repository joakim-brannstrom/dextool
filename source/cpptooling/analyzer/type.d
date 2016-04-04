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
import std.typecons : Tuple, Nullable, Flag;
import logger = std.experimental.logger;

import cpptooling.data.symbol.types : USRType;
import cpptooling.data.type : Location;

alias TypeKindAttr = Tuple!(TypeKind, "kind", TypeAttr, "attr");
alias TypeResult = Tuple!(TypeKindAttr, "primary", TypeKindAttr[], "extra");
alias FuncInfoParam = Tuple!(USRType, "usr", TypeAttr, "attr", string, "id",
        Flag!"isVariadic", "isVariadic");
alias ArrayInfoIndex = Nullable!long;

ref TypeResult mergeExtra(ref return TypeResult lhs, const ref TypeResult rhs) {
    lhs.extra ~= rhs.extra;
    return lhs;
}

/// Convert an array of indexes to a string representation
string toRepr(const(ArrayInfoIndex[]) index_nr) @safe pure {
    import std.algorithm : map, joiner;
    import std.conv : text;

    return index_nr.map!(a => a.isNull ? "[]" : "[" ~ text(a.get) ~ "]").joiner.text;
}

void logTypeAttr(const ref TypeAttr attr, in uint indent = 0,
        in string func = __FUNCTION__, in uint line = __LINE__) @safe pure {
    import std.array : array;
    import std.range : repeat;
    import logger = std.experimental.logger;
    import clang.info;

    // dfmt off
    debug {
        string indent_ = repeat(' ', indent).array();
        logger.logf!(-1, "", "", "", "")
            (logger.LogLevel.trace,
             "%d%s const:%s|ref:%s|ptr:%s|arr:%s|rec:%s|prim:%s|fptr:%s [%s:%d]",
             indent,
             indent_,
             attr.isConst,
             attr.isRef,
             attr.isPtr,
             attr.isArray,
             attr.isRecord,
             attr.isPrimitive,
             attr.isFuncPtr,
             func,
             line);
    }
    // dfmt on
}

void logTypeResult(const ref Nullable!TypeResult result, in uint indent = 0,
        in string func = __FUNCTION__, in uint line = __LINE__) @safe pure {
    debug {
        if (!result.isNull) {
            logTypeResult(result.get, indent, func, line);
        }
    }
}

void logTypeResult(const ref TypeResult result, in uint indent = 0,
        in string func = __FUNCTION__, in uint line = __LINE__) @safe pure {
    import std.array : array;
    import std.conv : to;
    import std.range : repeat, chain, only;
    import logger = std.experimental.logger;

    // dfmt off
    debug {
        string indent_ = repeat(' ', indent).array();
        foreach (const ref tka; chain(only(result.primary), result.extra)) {
            string extra;
            switch (tka.kind.info.kind) with (TypeKind.Info) {
            case Kind.typeRef:
                extra = "|ex ref:" ~ cast(string) tka.kind.info.typeRef ~ "|ex canonical:" ~ cast(string) tka.kind.info.canonicalRef;
                break;
            case Kind.pointer:
                extra = "|ex usr:" ~ cast(string) tka.kind.info.pointee;
                break;
            default:
            }

            logger.logf!(-1, "", "", "", "")
                (logger.LogLevel.trace,
                 "%d%s %s|%s|repr:%s|loc:%s|usr:%s|%s%s [%s:%d]",
                 indent,
                 indent_,
                 to!string(tka.kind.info.kind),
                 tka.kind.internalGetFmt,
                 tka.toStringDecl("x"),
                 tka.kind.loc.file.length == 0 ? "no" : "yes",
                 cast(string) tka.kind.usr,
                 tka.attr,
                 extra,
                 func,
                 line);

            switch (tka.kind.info.kind) with (TypeKind.Info) {
            case Kind.func:
                foreach (r; tka.kind.info.params) {
                    logTypeAttr(r.attr, indent + 1);
                }
                break;
            case Kind.pointer:
                foreach (r; tka.kind.info.attrs) {
                    logTypeAttr(r, indent + 1);
                }
                break;
            default:
            }
        }
    }
    // dfmt on
}

//TODO remove, this is not good. keep it focused on SimleInfo.
TypeKindAttr makeSimple(string txt, TypeAttr attr = TypeAttr.init) pure @safe nothrow {
    TypeKind t;
    t.info = TypeKind.SimpleInfo(txt ~ " %s");

    return TypeKindAttr(t, attr);
}

TypeKind makeSimple2(string txt) pure @safe nothrow {
    TypeKind t;
    t.info = TypeKind.SimpleInfo(txt ~ " %s");

    return t;
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
     * underlyingRef = usr of the canonical type
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
    USRType usr;
    Location loc;

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

/** Combine type attributes, kind and identifier to produce a declaration.
 * TODO reconsider the function name.
 *  - Don't encode the return type in the name (?)
 *  - Is it really a Decl-> declaration? Maybe more appropriate would be
 *    "merge", of type and attributes?
 */
auto toStringDecl(const TypeKind t, const TypeAttr ta, string id) {
    import std.format : formattedWrite;
    import std.array : appender;

    auto txt = appender!string();

    final switch (t.info.kind) with (TypeKind.Info) {
    case Kind.simple:
        txt.put(ta.isConst ? "const " : "");
        txt.formattedWrite(t.info.fmt, id);
        break;
    case Kind.typeRef:
        txt.put(ta.isConst ? "const " : "");
        txt.formattedWrite(t.info.fmt, id);
        break;
    case Kind.array:
        txt.put(t.info.elementAttr.isConst ? "const " : "");
        txt.formattedWrite(t.info.fmt, id, t.info.indexes.toRepr);
        break;
    case Kind.func:
        txt.formattedWrite(t.info.fmt, id);
        txt.put(ta.isConst ? " const" : "");
        break;
    case Kind.record:
        txt.put(ta.isConst ? "const " : "");
        txt.formattedWrite(t.info.fmt, id);
        break;
    case Kind.funcPtr:
        // a func ptr and pointer is formatted the same way
    case Kind.pointer:
        txt.put(ta.isConst ? "const " : "");
        auto ptrs = appender!string();
        foreach (attr; t.info.attrs) {
            // TODO merge isPtr/isRef to an enum in the data structure for
            // attributes
            // should be either, never both
            assert(!(attr.isPtr && attr.isRef));
            ptrs.put(attr.isPtr ? "*" : "");
            ptrs.put(attr.isRef ? "&" : "");

            ptrs.put(attr.isConst ? "const " : "");
        }
        txt.formattedWrite(t.info.fmt, ptrs.data, id);
        break;
    case Kind.ctor:
        // not affected by attr
        txt.formattedWrite(t.info.fmt, id);
        break;
    case Kind.dtor:
        // not affected by attr
        txt.formattedWrite(t.info.fmt, id);
        break;
    case Kind.null_:
        debug {
            logger.error("Type is null. Identifier ", id);
        }
        txt.put(id);
        break;

    }

    return txt.data;
}

/// ditto
auto toStringDecl(const TypeKind t, const TypeAttr ta) {
    import std.string : strip;

    // TODO consider changing the implementation of to NOT take an id.
    // Would avoid the strip....
    return t.toStringDecl(ta, "").strip;
}

/// if a type can be cast to a TypeKindAttr.
auto toStringDecl(T)(const T tka, string id)
        if (is(typeof(cast(TypeKindAttr) tka) == TypeKindAttr)) {
    return (cast(TypeKindAttr) tka).kind.toStringDecl(tka.attr, id);
}

/// ditto
auto toStringDecl(T)(const T tka)
        if (is(typeof(cast(TypeKindAttr) tka) == TypeKindAttr)) {
    return (cast(TypeKindAttr) tka).kind.toStringDecl(tka.attr);
}
