/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// This program is free software; you can redistribute it and/or modify
/// it under the terms of the GNU General Public License as published by
/// the Free Software Foundation; either version 2 of the License, or
/// (at your option) any later version.
///
/// This program is distributed in the hope that it will be useful,
/// but WITHOUT ANY WARRANTY; without even the implied warranty of
/// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
/// GNU General Public License for more details.
///
/// You should have received a copy of the GNU General Public License
/// along with this program; if not, write to the Free Software
/// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
module generator.stub.mangling;

import std.algorithm : canFind;
import std.array : join;
import std.conv : to;
import std.string : replace, strip;
import std.typecons : Nullable;

import logger = std.experimental.logger;

import clang.Cursor;

import translator.Type;

import generator.stub.types;

public:

///TODO future name changes.
/// Variable -> Identifier

/** Name mangling that occurs when translating to C++ code.
 */
enum NameMangling {
    Plain, // no mangling
    Callback,
    CallCounter,
    ReturnType
}

private auto cppOperatorToName(const CppMethodName name) pure nothrow @safe {
    Nullable!string r;

    switch (name.str) {
    case "operator=":
        r = "opAssign";
        break;
    default:
        break;
    }

    return r;
}

/// Null if it was unable to convert.
/// TODO change name of the function. Dunno anything better for now though...
/// But it is confusing
///
/// Example:
/// ---
/// mangleToVariable("operator=");
/// mangleToVariable("Foo");
/// ---
/// result is: opAssign and Foo
private auto mangleToVariable(const CppMethodName method) pure nothrow @safe {
    Nullable!string rval;

    if (canFind(method.str, "operator")) {
        auto callback_method = cppOperatorToName(method);

        if (!callback_method.isNull)
            rval = callback_method;
    }
    else {
        rval = method.str;
    }

    return rval;
}

/// Null if it was unable to convert.
/// Example:
/// ---
/// mangleToCallbackMethod("Foo", ["int x"]);
/// ---
/// result is: Foo_int
auto mangleToCallbackMethod(const CppMethodName method, TypeKindVariable[] params) pure @safe {
    import generator.stub.convert : toStringOfType;

    Nullable!CppMethodName rval;
    // same mangle schema but different return types so resuing but in a safe
    // manner not don't affect the rest of the program.
    auto tmp = mangleToVariable(method);
    if (!tmp.isNull) {
        rval = CppMethodName(tmp.get ~ params.toStringOfType);
    }

    return rval;
}

/// Null if it was unable to convert.
/// Example:
/// ---
/// mangleToReturnVariable("operator=");
/// mangleToReturnVariable("foo_bar");
/// ---
/// result is: opAssign_return and foo_bar_return
auto mangleToReturnVariable(const StubPrefix prefix) pure @safe {
    import std.string : toLower;

    return CppVariable(prefix.str.toLower ~ "_return");
}

/// Example:
/// ---
/// mangleTypeToCallbackStructType("const Foo&*");
/// ---
/// result is: Foo
auto mangleTypeToCallbackStructType(const CppType type) pure @safe {
    string r = (cast(string) type).replace("const", "");
    if (canFind(r, "&")) {
        r = r.replace("&", "") ~ "*";
    }

    return CppType(r.strip);
}

/// Example:
/// ---
/// mangleToStubStructType("Stub", "Foo", "Class_");
/// ---
/// result is: StubInternalClass_::StubFoo
auto mangleToStubStructType(const StubPrefix prefix, CppMethodName method, CppClassName class_name) {
    import std.string : format;

    return CppType(format("%sInternal%s::%s%s", prefix.str, class_name.str,
        prefix.str, method.str));
}

auto mangleToStubStructMemberType(const TypeKind tk) pure @safe {
    import generator.stub.misc : getPointerStars;

    string ptr = tk.getPointerStars;
    ptr ~= tk.isRef ? "*" : "";
    return CppType(tk.name ~ ptr);
}

CppVariable mangleToStubStructMember(const StubPrefix prefix,
    const NameMangling m, const CppVariable var) pure nothrow @safe {
    final switch (m) with (NameMangling) {
    case Plain:
        return var;
    case Callback:
        return CppVariable("callback");
    case CallCounter:
        return CppVariable("call_counter");
    case ReturnType:
        return CppVariable(prefix.str ~ "_return");
    }
}

CppMethodName mangleToStubStructIncrCounterMethod() pure nothrow @safe {
    return CppMethodName("IncrCallCounter");
}

CppMethodName mangleToStubStructGetMethod(const NameMangling m, const CppVariable var) pure nothrow @safe {
    final switch (m) with (NameMangling) {
    case Plain:
        return CppMethodName("Get" ~ var.str);
    case Callback:
        return CppMethodName("GetCallback");
    case CallCounter:
        return CppMethodName("GetCallCounter");
    case ReturnType:
        return CppMethodName("_return");
    }
}

/// Example:
/// ---
/// mangleToStubClassName("Stub", "Foo");
/// ---
/// result is: StubFoo
auto mangleToStubClassName(const StubPrefix prefix, const CppClassName name) pure nothrow @safe {
    return CppClassName(prefix ~ name);
}

/// Example:
/// ---
/// mangleToStubDataClass("Stub");
/// ---
/// result is: StubStubData
auto mangleToStubDataClass(const StubPrefix prefix) pure nothrow @safe {
    return CppClassName(prefix ~ prefix ~ "Data");
}

/// Example:
/// ---
/// mangleToStubDataClass("StubInternalSimple", "Stub");
/// ---
/// result is: StubStubData
auto mangleToStubDataClass(const StubNs ns, const StubPrefix prefix) pure nothrow @safe {
    return CppClassName(ns ~ "::" ~ mangleToStubDataClass(prefix).str);
}

/// Example:
/// ---
/// mangleToStubDataClassVariable("Stub");
/// ---
/// result is: Stub_data
auto mangleToStubDataClassVariable(const StubPrefix prefix) pure nothrow @safe {
    return CppVariable(prefix ~ "_data");
}

auto mangleToStubDataClassInternalVariable(const StubPrefix prefix, const CppMethodName method) pure @safe {
    import std.string : toLower;

    return CppVariable(prefix.str.toLower ~ "_" ~ method.str);
}

/// Example:
/// ---
/// mangleToStubDataGetter("Foo", [("int", "x")]);
/// ---
/// result is: Foo_int
auto mangleToStubDataGetter(const CppMethodName method, const TypeKindVariable[] params) nothrow @safe {
    import std.algorithm : map;
    import std.array : join;
    import generator.stub.convert : toStringOfType;

    string getter = method.str;

    // same mangle schema but different return types so resuing but in a safe
    // manner not don't affect the rest of the program.
    auto tmp = mangleToVariable(method);
    if (!tmp.isNull) {
        getter = tmp.get;
    }
    else {
        try {
            //TODO catch the specific exception thrown by logger instead of the
            /// "everything and kitchen sink" Exception.
            logger.errorf("Unable to mangle '%s'. Probably unsupported operator.",
                method.str);
        }
        catch (Exception ex) {
        }
        cast(void) tmp.get; // willfully crash
    }

    getter ~= params.toStringOfType;

    return CppMethodName(getter);
}

/// Example:
/// ---
/// ("foo");
/// ---
/// result is: param_foo
auto mangleToParamVariable(const CppVariable var_name) pure nothrow @safe {
    return CppVariable("Param_" ~ var_name.str);
}

/// Example:
/// ---
/// mangleToParamVariable(TypeKindVariable("whatever", "foo"));
/// ---
/// result is: param_foo
auto mangleToParamVariable(const TypeKindVariable tv) pure nothrow @safe {
    return CppVariable("Param_" ~ tv.name.str);
}

/** If the variable name is empty return a TypeName with a random name derived
 * from idx.
 */
auto genRandomName(const TypeName tn, ulong idx) {
    if ((cast(string) tn.name).strip.length == 0) {
        return TypeName(tn.type, CppVariable("x" ~ to!string(idx)));
    }

    return cast(TypeName) tn;
}

/// ditto
auto genRandomName(const TypeKindVariable tn, ulong idx) {
    if ((cast(string) tn.name).strip.length == 0) {
        return TypeKindVariable(cast(TypeKind) tn.type, CppVariable("x" ~ to!string(idx)));
    }

    return cast(TypeKindVariable) tn;
}
