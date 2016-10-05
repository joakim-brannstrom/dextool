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
import cpptooling.data.type; // : LocationTag;

public import cpptooling.analyzer.kind;

alias TypeKindAttr = Tuple!(TypeKind, "kind", TypeAttr, "attr");
alias TypeResult = Tuple!(TypeKindAttr, "type", LocationTag, "location");
alias TypeResults = Tuple!(TypeResult, "primary", TypeResult[], "extra");

/** Merge rhs into lhs.
 */
ref TypeResults mergeExtra(ref return TypeResults lhs, const ref TypeResults rhs) {
    lhs.extra ~= rhs.extra;
    return lhs;
}

/// Pretty loggning with indentation.
void logTypeAttr(const ref TypeAttr attr, in uint indent = 0, in uint extra_space = 0,
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
             "%d%s const:%s|ref:%s|ptr:%s|arr:%s|fptr:%s [%s:%d]",
             indent,
             indent_,
             attr.isConst,
             attr.isRef,
             attr.isPtr,
             attr.isArray,
             attr.isFuncPtr,
             func,
             line);
    }
    // dfmt on
}

/// Pretty loggning with indentation.
void logTypeResult(ref const(TypeResult) result, in uint indent,
        in string func = __FUNCTION__, in uint line = __LINE__) @safe pure {
    import std.array : array;
    import std.conv : to;
    import std.range : repeat;
    import logger = std.experimental.logger;

    // dfmt off
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
             "%d%s %s|%s|repr:%s|loc:%s|usr:%s|%s%s [%s:%d]",
             indent,
             indent_,
             to!string(result.type.kind.info.kind),
             result.type.kind.internalGetFmt,
             result.type.toStringDecl("x"),
             (result.location.kind == LocationTag.Kind.loc) ? (result.location.file.length == 0 ? "no" : "yes") : "noloc",
             cast(string) result.type.kind.usr,
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
    // dfmt on
}

/// Pretty loggning with indentation.
void logTypeResult(ref const(TypeResults) results, in uint indent = 0,
        in string func = __FUNCTION__, in uint line = __LINE__) @safe pure {
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
        in string func = __FUNCTION__, in uint line = __LINE__) @safe pure {
    debug {
        if (!results.isNull) {
            logTypeResult(results.get, indent, func, line);
        }
    }
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
    case Kind.primitive:
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
    case Kind.funcSignature:
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
