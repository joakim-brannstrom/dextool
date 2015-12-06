// Written in the D programming language.
/**
Date: 2015, Joakim Brännström
License: GPL
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

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
module cpptooling.generator.adapter;

import dsrcgen.cpp : CppModule;

import application.types : MainNs, MainInterface;
import cpptooling.data.representation : CppClass, CppNamespace, CxLocation;

@safe:

enum dummyLoc = CxLocation("<test double>", 0, 0);

/// Make a C++ adapter for an interface.
CppClass makeAdapter(InterfaceT, KindT)(InterfaceT if_name) {
    import cpptooling.data.representation;

    string c_if = cast(string) if_name;
    string c_name = "Adapter";

    auto c = CppClass(CppClassName(c_name));
    c.setKind(KindT.Adapter);

    auto param = makeCxParam(TypeKindVariable(makeTypeKind(c_if ~ "&", false,
        true, false), CppVariable("inst")));

    c.put("Adapter connecting an interface with an implementation.");
    c.put("The lifetime of the connection is the same as the instance of the adapter.");

    c.put(CppCtor(CppMethodName(c_name), [param], CppAccess(AccessType.Public)));
    c.put(CppDtor(CppMethodName("~" ~ c_name), CppAccess(AccessType.Public),
        CppVirtualMethod(VirtualType.No)));

    return c;
}

/// make an anonymous namespace containing a ptr to an instance of a test
/// double that implement the interface needed.
CppNamespace makeSingleton(KindT)(MainNs main_ns, MainInterface main_if) {
    import cpptooling.data.representation : makeTypeKind, CppVariable,
        CxGlobalVariable;
    import cpptooling.utility.conv : str;

    auto type = makeTypeKind(main_ns.str ~ "::" ~ main_if.str ~ "*", false, false,
        true);
    auto v = CxGlobalVariable(type, CppVariable("test_double_inst"), dummyLoc);
    auto ns = CppNamespace.makeAnonymous();
    ns.setKind(KindT.TestDoubleSingleton);
    ns.put(v);

    return ns;
}

/** Generate an adapter implementation.
 *
 * Expecting c to only have a c'tor and d'tor.
 * The global is expected to be named test_double_inst.
 */
void generateImpl(CppClass c, CppModule impl) {
    import std.variant : visit;
    import cpptooling.data.representation;
    import cpptooling.utility.conv : str;
    import dsrcgen.c : E;

    // C'tor is expected to have one parameter.
    static void genCtor(CppClass c, CppCtor m, CppModule impl) {
        // dfmt off
        TypeKindVariable p0 = () @trusted {
            return m.paramRange().front.visit!(
                (TypeKindVariable tkv) => tkv,
                (TypeKind tk) => TypeKindVariable(tk, CppVariable("inst")),
                (VariadicType vt) {
                    logger.error("Variadic c'tor not supported:", m.toString);
                    return TypeKindVariable(makeTypeKind("not supported", false,
                        false, false), CppVariable("not supported"));
                })();
        }();
        // dfmt on

        with (impl.ctor_body(m.name.str, E(p0.type.toString) ~ E(p0.name.str))) {
            stmt(E("test_double_inst") = E("&" ~ p0.name.str));
        }
        impl.sep(2);
    }

    //TODO not implemented generator for operators
    static void genOp(CppClass c, CppMethodOp m, CppModule impl) {
    }

    static void genDtor(CppClass c, CppDtor m, CppModule impl) {
        with (impl.dtor_body(c.name.str)) {
            stmt("test_double_inst = 0");
        }
        impl.sep(2);
    }

    static void genMethod(CppClass c, CppMethod m, CppModule impl) {
        import std.range : takeOne;

        string params = m.paramRange().joinParams();
        auto b = impl.method_body(m.returnType().toString, c.name().str,
            m.name().str, m.isConst(), params);
        with (b) {
            auto p = m.paramRange().joinParamNames();
            stmt(E("test_double_inst") = E("&" ~ p));
        }
        impl.sep(2);
    }

    foreach (m; c.methodPublicRange()) {
        // dfmt off
        () @trusted{
            m.visit!((CppMethod m) => genMethod(c, m, impl),
                    (CppMethodOp m) => genOp(c, m, impl),
                    (CppCtor m) => genCtor(c, m, impl),
                    (CppDtor m) => genDtor(c, m, impl));
        }();
        // dfmt on
    }
}

/// A singleton to allow the adapter to setup "a" connection.
void generateSingleton(CppNamespace in_ns, CppModule impl) {
    import std.ascii : newline;
    import cpptooling.utility.conv : str;
    import dsrcgen.cpp : E;

    auto ns = impl.namespace("")[$.begin = "{" ~ newline];
    ns.suppressIndent(1);
    impl.sep(2);

    foreach (g; in_ns.globalRange()) {
        auto stmt = E(g.type().toString ~ " " ~ g.name().str);
        if (g.type().isPointer) {
            stmt = E("0");
        }
        ns.stmt(stmt);
    }
}
