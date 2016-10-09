/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.data.type;

import std.traits; // : isSomeString;
import std.typecons; // : Tuple, Flag;
import std.variant; // : Algebraic;

import cpptooling.analyzer.type; // : TypeKind, TypeKindAttr, TypeResult;
import cpptooling.data.symbol.types; // : USRType;
import cpptooling.utility.taggedalgebraic;

static import cpptooling.data.class_classification;

/// Name of a C++ namespace.
struct CppNs {
    string payload;
    alias payload this;
}

/// Stack of nested C++ namespaces.
struct CppNsStack {
    CppNs[] payload;
    alias payload this;

    T opCast(T : CppNs[])() {
        return payload;
    }

    T opCast(T : const(CppNs)[])() const {
        return payload;
    }
}

/// Nesting of C++ namespaces as a string.
struct CppNsNesting {
    string payload;
    alias payload this;
}

struct CppVariable {
    string payload;
    alias payload this;
}

//TODO change to using TypeAttr or TypeKindAttr
alias TypeKindVariable = Tuple!(TypeKindAttr, "type", CppVariable, "name");

// Types for classes
struct CppClassName {
    string payload;
    alias payload this;
}

///TODO should be Optional type, either it has a nesting or it is "global".
/// Don't check the length and use that as an insidential "no nesting".
struct CppClassNesting {
    string payload;
    alias payload this;
}

// Types for methods
struct CppMethodName {
    string payload;
    alias payload this;
}

struct CppConstMethod {
    bool payload;
    alias payload this;
}

struct CppVirtualMethod {
    MemberVirtualType payload;
    alias payload this;
}

struct CppAccess {
    AccessType payload;
    alias payload this;

    T opCast(T)() const if (isSomeString!T) {
        import std.conv : to;

        return payload.to!T();
    }
}

// Types for free functions
struct CFunctionName {
    string payload;
    alias payload this;
}

// Shared types between C and Cpp
alias VariadicType = Flag!"isVariadic";
alias CxParam = Algebraic!(TypeKindVariable, TypeKindAttr, VariadicType);

struct CxReturnType {
    TypeKindAttr payload;
    alias payload this;
}

/// Locaiton of a symbol.
struct Location {
    import std.format : FormatSpec;

    ///
    string file;
    ///
    uint line;
    ///
    uint column;

    /// Create a file with default line and column
    this(string file) @safe {
        this(file, 0, 0);
    }

    ///
    this(string file, uint line, uint column) @safe {
        //TODO remove idup if it isn't needed
        this.file = file;
        this.line = line;
        this.column = column;
    }

    /// Location as File Line Column
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

    /// ditto
    void toString(Writer, Char)(scope Writer w, FormatSpec!Char formatSpec) const {
        import std.format : formatValue;
        import std.range.primitives : put;

        put(w, "File:");
        formatValue(w, file, formatSpec);
        put(w, " Line:");
        formatValue(w, line, formatSpec);
        put(w, " Column:");
        formatValue(w, column, formatSpec);
    }

    ///
    T opCast(T : string)() @safe pure const nothrow {
        return toString();
    }
}

/** Represent a location.
 *
 * Either a:
 *  - no location.
 *  - location with data.
 *
 * Using a TaggedAlgebraic to allow adding more types in the future.
 */
struct LocationTag {
    import std.format : FormatSpec;

    enum Kind {
        noloc,
        loc
    }

    /// Kind stored. Only use the payload when kind is "loc".
    Kind kind;

    ///
    Location payload;
    alias payload this;

    /// Create either a noloc instance when passed null or a location.
    this(T)(T t) @safe pure {
        static if (is(T == typeof(null))) {
            this.kind = Kind.noloc;
        } else {
            this.kind = Kind.loc;
            this.payload = t;
        }
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

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char formatSpec) const {
        import std.format : formatValue;
        import std.range.primitives : put;

        final switch (kind) {
        case Kind.noloc:
            put(w, "noloc");
            break;
        case Kind.loc:
            put(w, this.payload.toString);
            break;
        }
    }
}

auto toString(const ref LocationTag data) @safe pure {
    static import std.format;

    final switch (data.kind) {
    case LocationTag.Kind.noloc:
        return "noloc";
    case LocationTag.Kind.loc:
        return data.toString;
    }
}

//TODO change name to MethodVirtualType
enum MemberVirtualType {
    Unknown,
    Normal,
    Virtual,
    Pure
}

enum AccessType {
    Public,
    Protected,
    Private
}

enum StorageClass {
    None,
    Extern,
    Static
}

/// Convert a namespace stack to a string separated by ::.
string toStringNs(CppNsStack ns) @safe {
    import std.algorithm : map;
    import std.array : join;

    return ns.map!(a => cast(string) a).join("::");
}
