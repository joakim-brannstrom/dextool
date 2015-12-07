// Written in the D programming language.
/**
Date: 2015, Joakim Brännström
License: GPL
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Generate a google mock implementation of a pure C++ interface.

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
module cpptooling.generator.gmock;

import dsrcgen.cpp : CppModule;

import cpptooling.data.representation : CppClass;

@safe:

/// Assuming that in_c is pure virtual. Therefor the logic is simpler.
/// TODO add support for const functions.
void generateGmock(ParamT)(CppClass in_c, CppModule hdr, ParamT params)
in {
    import std.algorithm : among;
    import cpptooling.data.representation : VirtualType;

    assert(in_c.virtualType.among(VirtualType.Pure, VirtualType.Yes));
}
body {
    import std.algorithm : each;
    import std.conv : text;
    import std.format : format;
    import std.variant : visit;

    import cpptooling.data.representation;
    import cpptooling.utility.conv : str;

    static string gmockMethod(T)(T m) {
        // defensive code, I don't think this can happen
        logger.errorf(m.paramRange().length > 10,
            "%s: Too many parameters in function to generate a correct google mock. Nr:%d",
            m.name, m.paramRange().length);

        auto len = m.paramRange().length.text;
        switch (m.isConst) {
        case true:
            return "MOCK_CONST_METHOD" ~ len;
        default:
            return "MOCK_METHOD" ~ len;
        }
    }

    static void ignore() {
    }

    static void genOp(CppMethodOp m, CppModule hdr) {
        import cpptooling.data.representation : VirtualType;

        static string translateOp(string op) {
            switch (op) {
            case "=":
                return "opAssign";
            case "==":
                return "opEquals";
            default:
                logger.errorf(
                    "Operator '%s' is not supported. Create an issue on github containing the operator and example code.",
                    op);
                return "operator not supported";
            }
        }

        static void genMockMethod(CppMethodOp m, CppModule hdr) {
            string params = m.paramRange().joinParams();
            string gmock_name = translateOp(m.op().str);
            string gmock_method = gmockMethod(m);
            string stmt = format("%s(%s, %s(%s))", gmock_method, gmock_name,
                m.returnType().toString, params);
            hdr.stmt(stmt);
        }

        static void genCallMock(CppMethodOp m, CppModule hdr) {
            import dsrcgen.cpp : E;

            string gmock_name = translateOp(m.op().str);

            CppModule code = hdr.method_inline(true, m.returnType.toString,
                m.name.str, m.isConst, m.paramRange().joinParams());
            auto call = E(gmock_name)(m.paramRange().joinParamNames);

            if (m.returnType().toString == "void") {
                code.stmt(call);
            } else {
                code.return_(call);
            }
        }

        genMockMethod(m, hdr);
        genCallMock(m, hdr);
    }

    static void genMethod(CppMethod m, CppModule hdr) {
        import cpptooling.data.representation : VirtualType;

        logger.errorf(m.paramRange().length > 10,
            "%s: Too many parameters in function to generate a correct google mock. Nr:%d",
            m.name, m.paramRange().length);

        string params = m.paramRange().joinParams();
        string name = m.name().str;
        string gmock_method = gmockMethod(m);
        string stmt = format("%s(%s, %s(%s))", gmock_method, name,
            m.returnType().toString, params);

        hdr.stmt(stmt);
    }

    auto ns = hdr.namespace(params.getMainNs().str);
    ns.suppressIndent(1);
    auto c = ns.class_("Mock" ~ in_c.name().str, "public " ~ in_c.name().str);
    auto pub = c.public_();

    foreach (m; in_c.methodRange()) {
        // dfmt off
        () @trusted {
        m.visit!((CppMethod m) => genMethod(m, pub),
                 (CppMethodOp m) => genOp(m, pub),
                 (CppCtor m) => ignore(),
                 (CppDtor m) => ignore());
        }();
        // dfmt on
    }
    hdr.sep(2);
}

auto generateGmockHdr(FileT)(FileT if_file, FileT incl_guard, CppModule gmock) {
    import std.path : baseName;
    import dsrcgen.cpp : CppHModule;
    import cpptooling.generator.includes : convToIncludeGuard;

    auto o = CppHModule(convToIncludeGuard(incl_guard));
    o.content.include(((cast(string) if_file).baseName));
    o.content.include("gmock/gmock.h");
    o.content.sep(2);
    o.content.append(gmock);

    return o;
}

auto makeGmock(ClassT)(CppClass c) {
    import std.variant : visit;
    import cpptooling.data.representation;

    // Make all protected and private public to allow testing, for good and
    // bad
    static auto conv(T)(T m_) if (is(T == CppMethod) || is(T == CppMethodOp)) {
        import std.array : array;

        auto params = m_.paramRange.array();
        auto m = CppMethod(m_.name, params, m_.returnType,
            CppAccess(AccessType.Public), CppConstMethod(m_.isConst),
            CppVirtualMethod(VirtualType.Pure));
        return m;
    }

    auto rclass = CppClass(c.name, c.location, c.inherits);
    rclass.setKind(ClassT.Gmock);
    //dfmt off
    foreach (m_in; c.methodRange) {
        () @trusted{
            m_in.visit!((CppMethod m) => m.isVirtual ? rclass.put(conv(m)) : false,
                        (CppMethodOp m) => m.isVirtual ? rclass.put(conv(m)) : false,
                        (CppCtor m) {},
                        (CppDtor m) => m.isVirtual ? rclass.put(m) : false);
        }();
    }
    //dfmt on

    return rclass;
}
