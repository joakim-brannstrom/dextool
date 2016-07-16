// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.data.type;

import std.typecons : Typedef, Tuple, Flag;
import std.variant : Algebraic;

import cpptooling.analyzer.type : TypeKind, TypeKindAttr, TypeResult;
import cpptooling.data.symbol.types : USRType;
import cpptooling.utility.taggedalgebraic;

/// Name of a C++ namespace.
alias CppNs = Typedef!(string, null, "CppNs");
/// Stack of nested C++ namespaces.
alias CppNsStack = CppNs[];
/// Nesting of C++ namespaces as a string.
alias CppNsNesting = Typedef!(string, null, "CppNsNesting");

alias CppVariable = Typedef!(string, null, "CppVariable");
//TODO change to using TypeAttr or TypeKindAttr
alias TypeKindVariable = Tuple!(TypeKindAttr, "type", CppVariable, "name");

// Types for classes
alias CppClassName = Typedef!(string, null, "CppClassName");

///TODO should be Optional type, either it has a nesting or it is "global".
/// Don't check the length and use that as an insidential "no nesting".
alias CppClassNesting = Typedef!(string, null, "CppNesting");

alias CppClassVirtual = Typedef!(ClassVirtualType, ClassVirtualType.Unknown, "CppClassVirtual");

// Types for methods
alias CppMethodName = Typedef!(string, null, "CppMethodName");
alias CppConstMethod = Typedef!(bool, bool.init, "CppConstMethod");
alias CppVirtualMethod = Typedef!(MemberVirtualType, MemberVirtualType.Unknown, "CppVirtualMethod");
alias CppAccess = Typedef!(AccessType, AccessType.Private, "CppAccess");

// Types for free functions
alias CFunctionName = Typedef!(string, string.init, "CFunctionName");

// Shared types between C and Cpp
alias VariadicType = Flag!"isVariadic";
alias CxParam = Algebraic!(TypeKindVariable, TypeKindAttr, VariadicType);
alias CxReturnType = Typedef!(TypeKindAttr, TypeKindAttr.init, "CxReturnType");

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

enum MemberVirtualType {
    Unknown,
    Normal,
    Virtual,
    Pure
}

///TODO is ClassClassificationType better?
enum ClassVirtualType {
    Unknown,
    Normal,
    Virtual,
    VirtualDtor, // only one method, a d'tor and it is virtual
    Abstract,
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
