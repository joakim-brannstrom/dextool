/**
Date: 2015-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Utilities for translation, making and generation of test doubles for functions.
*/
module cpptooling.generator.func;

import logger = std.experimental.logger;

import dsrcgen.cpp : CppModule;

import dextool.type : MainInterface;
import cpptooling.data : CFunction, CppClass, CppClassName, CppNsStack;

@safe:

/// Generates a C implementation calling the test double via the matching
/// interface.
void generateFuncImpl(CFunction f, CppModule impl) {
    import cpptooling.data : joinParams, joinParamNames, toStringDecl;
    import dsrcgen.c : E;

    // assuming that a function declaration void a() in C is meant to be void
    // a(void), not variadic.
    string params;
    auto p_range = f.paramRange();
    if (p_range.length == 1 && !f.isVariadic || p_range.length > 1) {
        params = joinParams(p_range);
    }
    string names = joinParamNames(f.paramRange());

    with (impl.func_body(f.returnType.toStringDecl, f.name, params)) {
        if (f.returnType.toStringDecl == "void") {
            stmt(E("test_double_inst->" ~ f.name)(names));
        } else {
            return_(E("test_double_inst->" ~ f.name)(names));
        }
    }
    impl.sep(2);
}

/** Create a C++ interface of funcs in range to allow the user to supply an
 * implementation.
 */
CppClass makeFuncInterface(Tr)(Tr r, const CppClassName main_if) {
    import cpptooling.data.type : CppNs;

    return makeFuncInterface(r, main_if, CppNsStack(CppNs[].init));
}

/** Create a C++ interface of funcs in range to allow the user to supply an
 * implementation.
 *
 * Params:
 *  r = InputRange of functions the class is intended to wrap.
 *  name = the name of the class.
 *  ns = namespace the class reside in
 */
CppClass makeFuncInterface(Tr)(Tr r, const CppClassName name, const CppNsStack ns) {
    import cpptooling.data.representation;
    import std.array : array;

    auto c = CppClass(name, CppInherit[].init, ns);
    c.put(CppDtor(makeUniqueUSR, CppMethodName("~" ~ name),
            CppAccess(AccessType.Public), CppVirtualMethod(MemberVirtualType.Virtual)));

    foreach (f; r) {
        auto params = f.paramRange().array();
        if (f.isVariadic) {
            params = params[0 .. $ - 1];
        }

        auto meth_name = CppMethodName(f.name);
        auto m = CppMethod(f.usr.get, meth_name, params, f.returnType(),
                CppAccess(AccessType.Public), CppConstMethod(false),
                CppVirtualMethod(MemberVirtualType.Pure));

        c.put(m);
    }

    return c;
}
