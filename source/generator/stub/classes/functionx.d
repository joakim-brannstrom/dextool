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
module generator.stub.classes.functionx;

import std.algorithm : map, startsWith;
import std.array : array;
import std.conv : to;
import std.string : removechars;

import clang.c.index;
import clang.Cursor;

import dsrcgen.cpp;

import translator.Type : TypeKind, translateType;

import generator.stub.convert : toParamString, toStringOfName;
import generator.stub.containers;
import generator.stub.mangling;
import generator.stub.misc : paramDeclToTypeKindVariable;
import generator.stub.types;

import unit_threaded : name;

version (unittest) {
    import test.helpers : shouldEqualPretty;
    import unit_threaded : shouldEqual;
}

void functionTranslator(Cursor c, const StubPrefix prefix,
    const CppClassName class_name, ref VariableContainer vars,
    ref CallbackContainer callbacks, ref CppModule hdr, ref CppModule impl) {

    TypeKindVariable[] params;
    TypeKind return_type;
    CppMethodName method;
    CppMethodName callback_method;

    analyzeCursor(c, params, return_type, method, callback_method);
    string return_type_ = return_type.toString;

    pushVarsForCallback(params, callback_method, return_type_, vars, callbacks);

    doHeader(c.func.isVirtual, c.func.isConst, params, return_type_, method, hdr);
    doImpl(c.func.isConst, prefix, params, CppType(return_type_), class_name,
        method, callback_method, impl);
}

private:

void pushVarsForCallback(const TypeKindVariable[] params,
    const CppMethodName callback_method, const string return_type,
    ref VariableContainer vars, ref CallbackContainer callbacks) {
    vars.push(NameMangling.Callback, cast(CppType) callback_method,
        cast(CppVariable) callback_method, callback_method);
    vars.push(NameMangling.CallCounter, CppType("unsigned"),
        cast(CppVariable) callback_method, callback_method);

    TypeName[] p = params.map!(a => TypeName(mangleToStubStructMemberType(a.type),
        CppVariable(mangleToParamVariable(a).str))).array();
    vars.push(NameMangling.Plain, p, callback_method);

    if (return_type.strip != "void") {
        vars.push(NameMangling.ReturnType,
            mangleTypeToCallbackStructType(CppType(return_type)),
            cast(CppVariable) callback_method, callback_method);
    }

    callbacks.push(CppType(return_type), callback_method, params);
}

/// Extract data needed for code generation.
void analyzeCursor(Cursor c, out TypeKindVariable[] params,
    out TypeKind return_type, out CppMethodName method, out CppMethodName callback_method_) {
    auto params2 = paramDeclToTypeKindVariable(c);

    foreach (idx, tn; params2) {
        params ~= genRandomName(tn, idx);
    }
    return_type = translateType(c.func.resultType);
    method = CppMethodName(c.spelling);

    // if null results in a crash with the error message below
    auto callback_method = mangleToCallbackMethod(CppMethodName(c.spelling), params2);
    if (callback_method.isNull) {
        logger.errorf("Generating callback function for '%s' not supported", c.spelling);
        callback_method = CppMethodName("/* not supported '" ~ c.spelling ~ "' */");
    }
    callback_method_ = callback_method.get;
}

void doHeader(bool is_virtual, bool is_const, const TypeKindVariable[] params,
    const string return_type, const CppMethodName method, ref CppModule hdr) {
    hdr.method(is_virtual, return_type, method.str, is_const, params.toParamString);
}

auto castAndStoreValue(const TypeKindVariable v) @safe {
    import generator.stub.misc : getPointerStars;

    string get_ptr = v.type.isRef ? "&" : "";
    bool do_const_cast = v.type.isConst && (v.type.isRef || v.type.isPointer);

    if (do_const_cast) {
        string stars = v.type.getPointerStars;

        if (v.type.isRef) {
            stars ~= '*';
        }
        string without_const = v.type.name ~ stars;

        return E("const_cast<" ~ without_const ~ ">")(get_ptr ~ v.name);
    }
    return get_ptr ~ v.name.str;
}

@name("Test helper for parameter casting when storing parameters")
unittest {
    auto kind = TypeKind("int", false, false, false, "int");
    auto rval = castAndStoreValue(TypeKindVariable(kind, CppVariable("bar")));
    shouldEqual(rval, "bar");
}

@name("Test helper for parameter casting of ref and ptr")
unittest {
    auto kind = TypeKind("int", false, false, true, "int*");

    auto rval = castAndStoreValue(TypeKindVariable(kind, CppVariable("bar")));
    shouldEqual(rval, "bar");

    kind = TypeKind("int", false, true, false, "int&");
    rval = castAndStoreValue(TypeKindVariable(kind, CppVariable("bar")));
    shouldEqual(rval, "&bar");
}

@name("Test helper for const parameter casting of ref")
unittest {
    auto kind = TypeKind("int", true, false, true, "const int*");
    auto rval = castAndStoreValue(TypeKindVariable(kind, CppVariable("bar")));
    shouldEqual(rval, "const_cast<int*>(bar)");
}

@name("Test helper for const parameter casting of ptr")
unittest {
    auto kind = TypeKind("int", true, true, false, "const int&");
    auto rval = castAndStoreValue(TypeKindVariable(kind, CppVariable("bar")));
    assert(rval == "const_cast<int*>(&bar)", rval);
}

void doImpl(bool is_const, const StubPrefix prefix, const TypeKindVariable[] params,
    const CppType return_type, const CppClassName class_name,
    const CppMethodName method_, const CppMethodName callback_method, ref CppModule impl) {
    import std.algorithm : findAmong, map;

    auto data = mangleToStubDataClassVariable(prefix);
    auto getter = mangleToStubDataGetter(method_, params);
    auto counter = mangleToStubStructMember(prefix, NameMangling.CallCounter,
        CppVariable(method_.str));
    auto callback = mangleToStubStructMember(prefix, NameMangling.Callback,
        CppVariable(method_.str));

    auto func = impl.method_body(return_type.str, class_name.str, method_.str,
        is_const, params.toParamString);
    with (func) {
        stmt("%s.%s().%s++".format(mangleToStubDataClassVariable(prefix).str,
            getter.str, counter.str));
        // store parameters for the function in the static storage to be used by the user in test cases.
        foreach (a; params) {
            auto var = mangleToParamVariable(a.name).str;
            stmt(E(data.str).e(getter.str)("").e(var) = E(a.castAndStoreValue));
        }
        sep(2);

        if (return_type == CppType("void")) {
            with (if_(E(data.str).e(getter.str)("").e(callback.str) ~ E("!= 0"))) {
                stmt(
                    E(data.str).e(getter.str)("").e(callback.str ~ "->" ~ callback_method.str)(
                    params.toStringOfName));
            }
        } else {
            string star;
            if (findAmong(return_type.str, ['&']).length != 0) {
                star = "*";
            }
            with (if_(E(data.str).e(getter.str)("").e(callback.str) ~ E("!= 0"))) {
                return_(
                    E(data.str).e(getter.str)("").e(callback.str ~ "->" ~ callback_method.str)(
                    params.toStringOfName));
            }
            with (else_()) {
                return_(E(star ~ data.str).e(getter.str)("").e(mangleToReturnVariable(prefix).str));
            }
        }

    }

    impl.sep(2);
}
