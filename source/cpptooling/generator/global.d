/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.generator.global;

import application.types : MainInterface;
import cpptooling.data.representation : CppClass;
import cpptooling.data.symbol.types : USRType;

/** Make a C++ interface with a plain method for each item in the range.
 *
 */
CppClass makeGlobalInterface(RangeT)(RangeT range, const MainInterface main_if) @safe {
    import std.algorithm : map;
    import cpptooling.data.representation;
    import cpptooling.analyzer.type : makeSimple;

    auto globals_if = CppClass(CppClassName(main_if ~ "_InitGlobals"));
    globals_if.put(CppDtor(USRType("~" ~ globals_if.name), CppMethodName("~" ~ globals_if.name), CppAccess(AccessType.Public), CppVirtualMethod(MemberVirtualType.Virtual)));

    const void_ = CxReturnType(makeSimple("void"));

    foreach (method; range.map!(a => CppMethod(USRType(a.name), CppMethodName(a.name), CxParam[].init, void_, CppAccess(AccessType.Public), CppConstMethod(false), CppVirtualMethod(MemberVirtualType.Pure)))) {
        globals_if.put(method);
    }

    return globals_if;
}

@("Should be an interface of globals")
unittest {
    import std.array;
    import test.extra_should : shouldEqualPretty;
    import cpptooling.data.representation;
    import cpptooling.data.type;
    import cpptooling.analyzer.type;

    immutable dummyUSR = USRType("dummyUSR1");

    auto v0 = CxGlobalVariable(dummyUSR, TypeKindVariable(makeSimple("int"), CppVariable("x")));

    auto if_ = makeGlobalInterface([v0], MainInterface("TestDouble"));

    if_.toString.shouldEqualPretty("class TestDouble_InitGlobals { // Pure
public:
  virtual ~TestDouble_InitGlobals();
  virtual void x() = 0;
}; //Class:TestDouble_InitGlobals");
}
