// Written in the D programming language.
/**
Date: 2015, Joakim Brännström
License: GPL
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Utilities for translation, making and generation of test doubles for functions.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*/
module cpptooling.generator.func;

import logger = std.experimental.logger;

import dsrcgen.cpp : CppModule;

import application.types : MainInterface;
import cpptooling.data.representation : CFunction, CppClass;

@safe:

///TODO remove function, thus usage in cstub. see cppvariant rawFilter.
auto rawFilter(ControllerT, ProductsT)(CFunction func, ControllerT ctrl, ProductsT prod) {
    import application.types : FileName;
    import cpptooling.utility.nullvoid;

    NullableVoid!CFunction r;

    if (ctrl.doFile(func.location.file)) {
        r = func;
        prod.putLocation(FileName(func.location.file));
    } else {
        logger.info("Ignoring function: ", func.toString);
    }

    return r;
}

/// Generates a C implementation calling the test double via the matching
/// interface.
void generateFuncImpl(CFunction f, CppModule impl) {
    import cpptooling.data.representation : joinParams, joinParamNames;
    import cpptooling.utility.conv : str;
    import dsrcgen.c : E;

    // assuming that a function declaration void a() in C is meant to be void
    // a(void), not variadic.
    string params;
    auto p_range = f.paramRange();
    if (p_range.length == 1 && !f.isVariadic || p_range.length > 1) {
        params = joinParams(p_range);
    }
    string names = joinParamNames(f.paramRange());

    with (impl.func_body(f.returnType().toString, f.name().str, params)) {
        if (f.returnType().toString == "void") {
            stmt(E("test_double_inst->" ~ f.name().str)(E(names)));
        } else {
            return_(E("test_double_inst->" ~ f.name().str)(E(names)));
        }
    }
    impl.sep(2);
}

/** Create a C++ interface of funcs in range to allow the user to supply an
 * implementation.
 */
CppClass makeFuncInterface(Tr)(Tr r, in MainInterface main_if) {
    import cpptooling.data.representation;
    import cpptooling.utility.conv : str;

    import std.array : array;

    string c_name = cast(string) main_if;

    auto c = CppClass(CppClassName(c_name));

    foreach (f; r) {
        auto params = f.paramRange().array();
        if (f.isVariadic) {
            params = params[0 .. $ - 1];
        }

        auto name = CppMethodName(f.name.str);
        auto m = CppMethod(name, params, f.returnType(),
            CppAccess(AccessType.Public), CppConstMethod(false),
            CppVirtualMethod(VirtualType.Pure));

        c.put(m);
    }

    return c;
}
