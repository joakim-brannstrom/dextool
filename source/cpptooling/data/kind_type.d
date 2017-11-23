/**
Date: 2015-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Extracted information of types.
*/
module cpptooling.data.kind_type;

import std.conv : to;
import std.string : format;
import std.traits;
import std.typecons : Tuple, Nullable, Flag;
import logger = std.experimental.logger;

import cpptooling.data.symbol.types : USRType;
import cpptooling.data.type : LocationTag;

public import cpptooling.data.kind;

struct TypeKindAttr {
    TypeKind kind;
    TypeAttr attr;
}

struct TypeResult {
    TypeKindAttr type;
    LocationTag location;
}

struct TypeResults {
    TypeResult primary;
    TypeResult[] extra;
}

/** Merge rhs into lhs.
 */
ref TypeResults mergeExtra(ref return TypeResults lhs, const ref TypeResults rhs) {
    lhs.extra ~= rhs.extra;
    return lhs;
}

/// Pretty loggning with indentation.
void logTypeAttr(const ref TypeAttr attr, const uint indent = 0,
        in uint extra_space = 0, in string func = __FUNCTION__, in uint line = __LINE__) @trusted pure {
    import std.array : array;
    import std.range : repeat;
    import logger = std.experimental.logger;
    import clang.info;

    // dfmt off
    debug {
        string indent_ = repeat(' ', indent + extra_space).array();
        logger.logf!(-1, "", "", "", "")
            (logger.LogLevel.trace,
             "%d%s %s [%s:%d]",
             indent,
             indent_,
             attr,
             func,
             line);
    }
    // dfmt on
}

/// Pretty loggning with indentation.
void logTypeResult(ref const(TypeResult) result, in uint indent,
        in string func = __FUNCTION__, in uint line = __LINE__) @trusted pure nothrow {
    import std.array : array;
    import std.conv : to;
    import std.range : repeat;
    import logger = std.experimental.logger;

    // dfmt off
    try {
    debug {
        string indent_ = repeat(' ', indent).array();
        string extra;
        switch (result.type.kind.info.kind) with (TypeKind.Info) {
            case Kind.typeRef:
                extra = "|ex ref:" ~ result.type.kind.info.typeRef ~ "|ex canonical:" ~ result.type.kind.info.canonicalRef;
                break;
            case Kind.funcPtr:
            case Kind.pointer:
                extra = "|ex usr:" ~ result.type.kind.info.pointee;
                break;
            case Kind.array:
                extra = "|ex elem:" ~ result.type.kind.info.element;
                break;
            default:
        }

        logger.logf!(-1, "", "", "", "")
            (logger.LogLevel.trace,
             "%d%s %s|%s|repr:%s|loc:%s %s|usr:%s|%s%s [%s:%d]",
             indent,
             indent_,
             to!string(result.type.kind.info.kind),
             result.type.kind.splitTypeId,
             result.type.toStringDecl("x"),
             (result.location.kind == LocationTag.Kind.loc) ? (result.location.file.length == 0 ? "no" : "yes") : "noloc",
             (result.type.attr.isDefinition ? "def" : "decl"),
             result.type.kind.usr,
             result.type.attr,
             extra,
             func,
             line);

        switch (result.type.kind.info.kind) with (TypeKind.Info) {
            case Kind.func:
                foreach (r; result.type.kind.info.params) {
                    logTypeAttr(r.attr, indent, 1, func, line);
                }
                break;
            case Kind.pointer:
                foreach (r; result.type.kind.info.attrs) {
                    logTypeAttr(r, indent, 1, func, line);
                }
                break;
            default:
        }
    }
    } catch (Exception ex) {
    }
    // dfmt on
}

/// Pretty loggning with indentation.
void logTypeResult(ref const(TypeResults) results, in uint indent = 0,
        in string func = __FUNCTION__, in uint line = __LINE__) @safe pure nothrow {
    import std.range : chain, only;

    // dfmt off
    debug {
        foreach (const ref result; chain(only(results.primary), results.extra)) {
            logTypeResult(result, indent, func, line);
        }
    }
    // dfmt on
}

/// Pretty loggning with indentation.
void logTypeResult(ref const(Nullable!TypeResults) results, in uint indent = 0,
        in string func = __FUNCTION__, in uint line = __LINE__) @safe pure nothrow {
    debug {
        if (!results.isNull) {
            logTypeResult(results.get, indent, func, line);
        }
    }
}

//TODO remove, this is not good. keep it focused on SimleInfo.
TypeKindAttr makeSimple(string txt, TypeAttr attr = TypeAttr.init) pure @safe nothrow {
    import cpptooling.data : SimpleFmt, TypeId;

    TypeKind t;
    t.info = TypeKind.SimpleInfo(SimpleFmt(TypeId(txt)));

    return TypeKindAttr(t, attr);
}

private auto toCvPtrQ(T)(ref T app, const(TypeAttr)[] attrs) {
    import cpptooling.data;

    foreach (attr; attrs) {
        // TODO merge isPtr/isRef to an enum in the data structure for
        // attributes
        // should be either, never both
        assert(!(attr.isPtr && attr.isRef));

        CvPtrQ a;
        a.cvQual = attr.isConst ? CvQ.const_ : CvQ();
        if (attr.isPtr)
            a.ptrQual = PtrQ.ptr;
        else if (attr.isRef)
            a.ptrQual = PtrQ.ref_;

        app.put(a);
    }
}

/** Combine type attributes, kind and identifier to produce a declaration.
 * TODO reconsider the function name.
 *  - Don't encode the return type in the name (?)
 *  - Is it really a Decl-> declaration? Maybe more appropriate would be
 *    "merge", of type and attributes?
 */
auto toStringDecl(const TypeKind t, const TypeAttr ta, string id) @safe pure {
    import std.array : appender, Appender;
    import cpptooling.data;

    static void oneArg(T)(ref Appender!string app, ref T fmt, ref const TypeAttr ta, DeclId id) {
        fmt.toString(app, ta.isConst ? CvQ.const_ : CvQ(), id);
    }

    static void twoArg(T0, T1)(ref Appender!string app, ref T0 fmt,
            ref const TypeAttr ta, DeclId id, T1 data1) {
        fmt.toString(app, app, ta.isConst ? CvQ.const_ : CvQ(), data1, id);
    }

    auto txt = appender!string();

    // TODO sort them by alphabetic order

    final switch (t.info.kind) with (TypeKind.Info) {
    case Kind.primitive:
        auto info = cast(const TypeKind.PrimitiveInfo) t.info;
        oneArg(txt, info.fmt, ta, DeclId(id));
        break;
    case Kind.record:
        auto info = cast(const TypeKind.RecordInfo) t.info;
        oneArg(txt, info.fmt, ta, DeclId(id));
        break;
    case Kind.simple:
        auto info = cast(const TypeKind.SimpleInfo) t.info;
        oneArg(txt, info.fmt, ta, DeclId(id));
        break;
    case Kind.typeRef:
        auto info = cast(const TypeKind.TypeRefInfo) t.info;
        oneArg(txt, info.fmt, ta, DeclId(id));
        break;
    case Kind.array:
        auto info = cast(const TypeKind.ArrayInfo) t.info;
        ArraySize sz;

        foreach (a; info.indexes) {
            if (a.isNull) {
                sz ~= ArraySize.Size();
            } else {
                sz ~= ArraySize.Size(ArraySize.Kind.const_, a.get);
            }
        }

        info.fmt.toString(txt, txt, ta.isConst ? CvQ.const_ : CvQ(), DeclId(id), sz);
        break;
    case Kind.func:
        auto info = cast(const TypeKind.FuncInfo) t.info;
        info.fmt.toString(txt, txt, DeclId(id));
        break;
    case Kind.funcSignature:
        auto info = cast(const TypeKind.FuncSignatureInfo) t.info;
        info.fmt.toString(txt, txt);
        break;
    case Kind.funcPtr:
        auto ptrs = appender!(CvPtrQ[])();
        toCvPtrQ(ptrs, t.info.attrs);

        auto info = cast(const TypeKind.FuncPtrInfo) t.info;
        twoArg(txt, info.fmt, ta, DeclId(id), ptrs.data);
        break;
    case Kind.pointer:
        auto ptrs = appender!(CvPtrQ[])();
        toCvPtrQ(ptrs, t.info.attrs);

        auto info = cast(const TypeKind.PointerInfo) t.info;
        twoArg(txt, info.fmt, ta, DeclId(id), ptrs.data);
        break;
    case Kind.ctor:
        auto info = cast(const TypeKind.CtorInfo) t.info;
        info.fmt.toString(txt, DeclId(id));
        break;
    case Kind.dtor:
        auto info = cast(const TypeKind.DtorInfo) t.info;
        info.fmt.toString(txt, DeclId(id));
        break;
    case Kind.null_:
        () @trusted{ debug logger.error("Type is null. Identifier ", id); }();
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
auto toStringDecl(T)(const T value, string id)
        if (is(typeof(cast(TypeKindAttr) value) == TypeKindAttr)) {
    return (cast(TypeKindAttr) value).kind.toStringDecl(value.attr, id);
}

/// ditto
auto toStringDecl(T)(const T value)
        if (is(typeof(cast(TypeKindAttr) value) == TypeKindAttr)) {
    return (cast(TypeKindAttr) value).kind.toStringDecl(value.attr);
}

/** Split the TypeId from the formatter in a Left/Right.
 *
 * TODO duplicate code between this and toStringDecl.
 */
auto splitTypeId(ref const TypeKind t) @safe pure {
    import std.array : appender, Appender;
    import cpptooling.data;

    TypeIdLR rval;

    final switch (t.info.kind) with (TypeKind.Info) {
    case Kind.primitive:
        auto info = cast(const TypeKind.PrimitiveInfo) t.info;
        rval.left = info.fmt.typeId;
        break;
    case Kind.record:
        auto info = cast(const TypeKind.RecordInfo) t.info;
        rval.left = info.fmt.typeId;
        break;
    case Kind.simple:
        auto info = cast(const TypeKind.SimpleInfo) t.info;
        rval.left = info.fmt.typeId;
        break;
    case Kind.typeRef:
        auto info = cast(const TypeKind.TypeRefInfo) t.info;
        rval.left = info.fmt.typeId;
        break;
    case Kind.array:
        auto info = cast(const TypeKind.ArrayInfo) t.info;
        ArraySize sz;

        foreach (a; info.indexes) {
            if (a.isNull) {
                sz ~= ArraySize.Size();
            } else {
                sz ~= ArraySize.Size(ArraySize.Kind.const_, a.get);
            }
        }

        auto wl = appender!string();
        auto wr = appender!string();
        info.fmt.toString(wl, wr, CvQ(), DeclId(null), sz);
        rval = TypeIdLR(Left(wl.data), Right(wr.data));
        break;
    case Kind.funcSignature:
        auto info = cast(const TypeKind.FuncSignatureInfo) t.info;
        auto wl = appender!string();
        auto wr = appender!string();
        info.fmt.toString(wl, wr);
        rval = TypeIdLR(Left(wl.data), Right(wr.data));
        break;
    case Kind.func:
        auto info = cast(const TypeKind.FuncInfo) t.info;
        auto wl = appender!string();
        auto wr = appender!string();
        info.fmt.toString(wl, wr, DeclId(null));
        rval = TypeIdLR(Left(wl.data), Right(wr.data));
        break;
    case Kind.funcPtr:
        auto ptrs = appender!(CvPtrQ[])();
        toCvPtrQ(ptrs, t.info.attrs);

        auto info = cast(const TypeKind.FuncPtrInfo) t.info;
        auto wl = appender!string();
        auto wr = appender!string();
        info.fmt.toString(wl, wr, CvQ(), ptrs.data, DeclId(null));
        rval = TypeIdLR(Left(wl.data), Right(wr.data));
        break;
    case Kind.pointer:
        auto ptrs = appender!(CvPtrQ[])();
        toCvPtrQ(ptrs, t.info.attrs);

        auto info = cast(const TypeKind.PointerInfo) t.info;
        auto wl = appender!string();
        auto wr = appender!string();
        info.fmt.toString(wl, wr, CvQ(), ptrs.data, DeclId(null));
        rval = TypeIdLR(Left(wl.data), Right(wr.data));
        break;
    case Kind.ctor:
        // have no TypeId
        break;
    case Kind.dtor:
        // have no TypeId
        break;
    case Kind.null_:
        () @trusted{ debug logger.error("Type is null"); }();
        break;
    }

    return rval;
}

/// ditto
auto splitTypeId(ref const TypeKind t, const uint indent = 0) @safe pure
out (result) {
    import dextool.logger : trace;
    import std.conv : to;

    debug {
        trace(result.to!string(), indent);
    }
}
body {
    return splitTypeId(t);
}
