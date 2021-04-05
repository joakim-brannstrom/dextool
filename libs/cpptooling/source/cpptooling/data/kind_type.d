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
import std.typecons : Tuple, Flag, Nullable;
import logger = std.experimental.logger;

import sumtype;

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
ref TypeResults mergeExtra(ref return TypeResults lhs, ref TypeResults rhs) {
    lhs.extra ~= rhs.extra;
    return lhs;
}

/// Pretty loggning with indentation.
void logTypeAttr(TypeAttr attr, const uint indent = 0, in uint extra_space = 0,
        in string func = __FUNCTION__, in uint line = __LINE__) @safe pure {
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
void logTypeResult(const TypeResult result, in uint indent,
        in string func = __FUNCTION__, in uint line = __LINE__) @safe pure nothrow {
    import std.array : array;
    import std.conv : to;
    import std.range : repeat;
    import logger = std.experimental.logger;

    // dfmt off
    try {
    debug {
        string indent_ = repeat(' ', indent).array();
        string extra;
        result.type.kind.info.match!((const TypeKind.TypeRefInfo t) {
                extra = "|ex ref:" ~ t.typeRef ~ "|ex canonical:" ~ t.canonicalRef;
                                     },
                                     (const TypeKind.FuncPtrInfo t) {
                extra = "|ex usr:" ~ t.pointee;
                                     },
                                     (const TypeKind.PointerInfo t) {
                extra = "|ex usr:" ~ t.pointee;
                                     },
                                     (const TypeKind.ArrayInfo t) {
                extra = "|ex elem:" ~ t.element;
                                     },
                                     (_) {});

        logger.logf!(-1, "", "", "", "")
            (logger.LogLevel.trace,
             "%d%s %s|%s|repr:%s|loc:%s %s|usr:%s|%s%s [%s:%d]",
             indent,
             indent_,
             result.type.kind.info.match!(a => typeof(a).stringof),
             result.type.kind.splitTypeId,
             result.type.toStringDecl("x"),
             (result.location.kind == LocationTag.Kind.loc) ? (result.location.file.length == 0 ? "no" : "yes") : "noloc",
             (result.type.attr.isDefinition ? "def" : "decl"),
             result.type.kind.usr,
             result.type.attr,
             extra,
             func,
             line);

        result.type.kind.info.match!((const TypeKind.FuncInfo t) {
                foreach (r; t.params) {
                    logTypeAttr(r.attr, indent, 1, func, line);
                }
                                     },
                                     (const TypeKind.PointerInfo t) {
                foreach (r; t.attrs) {
                    logTypeAttr(r, indent, 1, func, line);
                }
                                     }, (_) {});
    }
    } catch (Exception ex) {
    }
    // dfmt on
}

/// Pretty loggning with indentation.
void logTypeResult(const TypeResults results, in uint indent = 0,
        in string func = __FUNCTION__, in uint line = __LINE__) @safe pure nothrow {
    // dfmt off
    debug {
        logTypeResult(results.primary, indent, func, line);
        foreach (ref result; results.extra) {
            logTypeResult(result, indent, func, line);
        }
    }
    // dfmt on
}

/// Pretty loggning with indentation.
void logTypeResult(const Nullable!TypeResults results, in uint indent = 0,
        in string func = __FUNCTION__, in uint line = __LINE__) @safe pure nothrow {
    debug {
        if (!results.isNull) {
            logTypeResult(results.get, indent, func, line);
        }
    }
}

//TODO remove, this is not good. keep it focused on SimleInfo.
TypeKindAttr makeSimple(string txt, TypeAttr attr = TypeAttr.init) pure @trusted nothrow {
    import cpptooling.data : SimpleFmt, TypeId;

    TypeKind t;
    t.info = TypeKind.Info(TypeKind.SimpleInfo(SimpleFmt(TypeId(txt))));

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
 *
 * trusted: shouldn't be needed but because of changes to dmd-2.094.0
 */
auto toStringDecl(const TypeKind t, TypeAttr ta, string id) @safe pure {
    import std.array : appender, Appender;
    import cpptooling.data;

    auto buf = appender!(char[])();
    void txt(const(char)[] s) @safe pure {
        buf.put(s);
    }

    void oneArg(T)(ref T fmt, ref const TypeAttr ta, DeclId id) {
        fmt.toString(&txt, ta.isConst ? CvQ.const_ : CvQ(), id);
    }

    void twoArg(T0, T1)(ref T0 fmt, ref const TypeAttr ta, DeclId id, T1 data1) {
        fmt.toString(&txt, &txt, ta.isConst ? CvQ.const_ : CvQ(), data1, id);
    }

    t.info.match!((const TypeKind.PrimitiveInfo t) => oneArg(t.fmt, ta,
            DeclId(id)), (const TypeKind.RecordInfo t) => oneArg(t.fmt, ta,
            DeclId(id)), (const TypeKind.SimpleInfo t) => oneArg(t.fmt, ta,
            DeclId(id)), (const TypeKind.TypeRefInfo t) => oneArg(t.fmt, ta,
            DeclId(id)), (const TypeKind.ArrayInfo t) {
        ArraySize sz;

        foreach (a; t.indexes) {
            if (a.isNull) {
                sz ~= ArraySize.Size();
            } else {
                sz ~= ArraySize.Size(ArraySize.Kind.const_, a.get);
            }
        }

        t.fmt.toString(&txt, &txt, ta.isConst ? CvQ.const_ : CvQ(), DeclId(id), sz);
    }, (const TypeKind.FuncInfo t) => t.fmt.toString(&txt, &txt, DeclId(id)),
            (const TypeKind.FuncSignatureInfo t) => t.fmt.toString(&txt,
                &txt), (const TypeKind.FuncPtrInfo t) {
        auto ptrs = appender!(CvPtrQ[])();
        toCvPtrQ(ptrs, t.attrs);

        twoArg(t.fmt, ta, DeclId(id), ptrs.data);
    }, (const TypeKind.PointerInfo t) {
        auto ptrs = appender!(CvPtrQ[])();
        toCvPtrQ(ptrs, t.attrs);

        twoArg(t.fmt, ta, DeclId(id), ptrs.data);
    }, (const TypeKind.CtorInfo t) => t.fmt.toString(&txt, DeclId(id)),
            (const TypeKind.DtorInfo t) => t.fmt.toString(&txt, DeclId(id)), (Void t) {
        debug {
            logger.error("Type is null. Identifier ", id);
        }
        txt(id);
    });

    return buf.data.idup;
}

/// ditto
auto toStringDecl(const TypeKind t, const TypeAttr ta) @safe {
    import std.string : strip;

    // TODO consider changing the implementation of to NOT take an id.
    // Would avoid the strip....
    return t.toStringDecl(ta, "").strip;
}

/// if a type can be cast to a TypeKindAttr.
auto toStringDecl(T)(T value, string id) @safe
        if (is(typeof(cast(TypeKindAttr) value) == TypeKindAttr)) {
    return (cast(const TypeKindAttr) value).kind.toStringDecl(value.attr, id);
}

/// ditto
auto toStringDecl(T)(T value) @safe
        if (is(typeof(cast(TypeKindAttr) value) == TypeKindAttr)) {
    return (cast(const TypeKindAttr) value).kind.toStringDecl(value.attr);
}

/** Split the TypeId from the formatter in a Left/Right.
 *
 * TODO duplicate code between this and toStringDecl.
 */
auto splitTypeId(const TypeKind t) @safe pure {
    import std.array : appender, Appender;
    import cpptooling.data;

    TypeIdLR rval;

    auto bufWl = appender!(char[])();
    void wl(const(char)[] s) @safe pure {
        bufWl.put(s);
    }

    auto bufWr = appender!(char[])();
    void wr(const(char)[] s) @safe pure {
        bufWr.put(s);
    }

    t.info.match!((const TypeKind.PrimitiveInfo t) { rval.left = t.fmt.typeId; },
            (const TypeKind.RecordInfo t) { rval.left = t.fmt.typeId; },
            (const TypeKind.SimpleInfo t) { rval.left = t.fmt.typeId; },
            (const TypeKind.TypeRefInfo t) { rval.left = t.fmt.typeId; },
            (const TypeKind.ArrayInfo t) {
        ArraySize sz;

        foreach (a; t.indexes) {
            if (a.isNull) {
                sz ~= ArraySize.Size();
            } else {
                sz ~= ArraySize.Size(ArraySize.Kind.const_, a.get);
            }
        }

        t.fmt.toString(&wl, &wr, CvQ(), DeclId(null), sz);
        rval = TypeIdLR(Left(bufWl.data.idup), Right(bufWr.data.idup));
    }, (const TypeKind.FuncSignatureInfo t) {
        t.fmt.toString(&wl, &wr);
        rval = TypeIdLR(Left(bufWl.data.idup), Right(bufWr.data.idup));
    }, (const TypeKind.FuncInfo t) {
        t.fmt.toString(&wl, &wr, DeclId(null));
        rval = TypeIdLR(Left(bufWl.data.idup), Right(bufWr.data.idup));
    }, (const TypeKind.FuncPtrInfo t) {
        auto ptrs = appender!(CvPtrQ[])();
        toCvPtrQ(ptrs, t.attrs);

        t.fmt.toString(&wl, &wr, CvQ(), ptrs.data, DeclId(null));
        rval = TypeIdLR(Left(bufWl.data.idup), Right(bufWr.data.idup));
    }, (const TypeKind.PointerInfo t) {
        auto ptrs = appender!(CvPtrQ[])();
        toCvPtrQ(ptrs, t.attrs);

        t.fmt.toString(&wl, &wr, CvQ(), ptrs.data, DeclId(null));
        rval = TypeIdLR(Left(bufWl.data.idup), Right(bufWr.data.idup));
    }, (_) {});

    return rval;
}

/// ditto
auto splitTypeId(const TypeKind t, in uint indent = 0) @safe pure
out (result) {
    import std.conv : to;

    debug {
        logger.trace(result.to!string(), indent);
    }
}
do {
    return splitTypeId(t);
}
