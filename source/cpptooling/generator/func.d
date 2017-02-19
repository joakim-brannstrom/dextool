// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Utilities for translation, making and generation of test doubles for functions.
*/
module cpptooling.generator.func;

import logger = std.experimental.logger;

import dsrcgen.cpp : CppModule;

import application.types : MainInterface;
import cpptooling.data.representation : CFunction, CppClass, CppClassName;
import cpptooling.data.symbol.types : USRType;

@safe:

/// Generates a C implementation calling the test double via the matching
/// interface.
void generateFuncImpl(CFunction f, CppModule impl) {
    import cpptooling.data.representation : joinParams, joinParamNames;
    import cpptooling.analyzer.type : toStringDecl;
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
            stmt(E("test_double_inst->" ~ f.name)(E(names)));
        } else {
            return_(E("test_double_inst->" ~ f.name)(E(names)));
        }
    }
    impl.sep(2);
}

/** Create a C++ interface of funcs in range to allow the user to supply an
 * implementation.
 */
CppClass makeFuncInterface(Tr)(Tr r, const CppClassName main_if) {
    import cpptooling.data.representation;

    import std.array : array;

    auto c = CppClass(main_if);
    c.put(CppDtor(makeUniqueUSR, CppMethodName("~" ~ main_if),
            CppAccess(AccessType.Public), CppVirtualMethod(MemberVirtualType.Virtual)));

    foreach (f; r) {
        auto params = f.paramRange().array();
        if (f.isVariadic) {
            params = params[0 .. $ - 1];
        }

        auto name = CppMethodName(f.name);
        auto m = CppMethod(f.usr, name, params, f.returnType(), CppAccess(AccessType.Public),
                CppConstMethod(false), CppVirtualMethod(MemberVirtualType.Pure));

        c.put(m);
    }

    return c;
}
