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
    import std.ascii : newline;
    import std.algorithm : each;
    import std.conv : text;
    import std.format : format;
    import std.variant : visit;

    import cpptooling.data.representation;
    import cpptooling.utility.conv : str;

    static string gmockMacro(size_t len, bool isConst)
    in {
        assert(len <= 10);
    }
    body {
        if (isConst)
            return "MOCK_CONST_METHOD" ~ len.text;
        else
            return "MOCK_METHOD" ~ len.text;
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
                logger.errorf("Operator '%s' is not supported. Create an issue on github containing the operator and example code.",
                        op);
                return "operator not supported";
            }
        }

        static void genMockMethod(CppMethodOp m, CppModule hdr) {
            string params = m.paramRange().joinParams();
            string gmock_name = translateOp(m.op().str);
            string gmock_macro = gmockMacro(m.paramRange().length, m.isConst);
            string stmt = format("%s(%s, %s(%s))", gmock_macro, gmock_name,
                    m.returnType().txt, params);
            hdr.stmt(stmt);
        }

        static void genMockCaller(CppMethodOp m, CppModule hdr) {
            import dsrcgen.cpp : E;

            string gmock_name = translateOp(m.op().str);

            CppModule code = hdr.method_inline(true, m.returnType.txt,
                    m.name.str, m.isConst, m.paramRange().joinParams());
            auto call = E(gmock_name)(m.paramRange().joinParamNames);

            if (m.returnType().txt == "void") {
                code.stmt(call);
            } else {
                code.return_(call);
            }
        }

        genMockMethod(m, hdr);
        genMockCaller(m, hdr);
    }

    static void genMethod(CppMethod m, CppModule hdr) {
        enum MAX_GMOCK_PARAMS = 10;

        void genMethodWithFewParams(CppMethod m, CppModule hdr) {
            hdr.stmt(format("%s(%s, %s(%s))", gmockMacro(m.paramRange().length,
                    m.isConst), m.name.str(), m.returnType().txt, m.paramRange().joinParams()));
            return;
        }

        void genMethodWithManyParams(CppMethod m, CppModule hdr) {
            import std.algorithm : each;
            import std.range : chunks, enumerate, dropBackOne;
            import dsrcgen.cpp : E;

            static string partName(string name, size_t part_no) {
                return format("%s_part_%s", name, part_no);
            }

            static void genPart(T)(size_t part_no, T a, CppMethod m,
                    CppModule code, CppModule delegate_mock) {
                // inject gmock macro
                code.stmt(format("%s(%s, void(%s))", gmockMacro(a.length,
                        m.isConst), partName(m.name().str, part_no), a.joinParams));
                //// inject delegation call to gmock macro
                delegate_mock.stmt(E(partName(m.name().str, part_no))(a.joinParamNames));
            }

            static void genLastPart(T)(size_t part_no, T p, CppMethod m,
                    CppModule code, CppModule delegate_mock) {
                auto part_name = partName(m.name().str, part_no);
                code.stmt(format("%s(%s, %s(%s))", gmockMacro(p.length,
                        m.isConst), part_name, m.returnType().txt, p.joinParams));

                auto stmt = E(part_name)(p.joinParamNames);

                if (m.returnType().txt == "void") {
                    delegate_mock.stmt(stmt);
                } else {
                    delegate_mock.return_(stmt);
                }
            }

            // Code block for gmock macros
            auto code = hdr.base();
            code.suppressIndent(1);

            // Generate mock method that delegates to partial mock methods
            auto delegate_mock = hdr.method_inline(true, m.returnType().txt,
                    m.name().str, m.isConst, m.paramRange().joinParams());

            auto param_chunks = chunks(m.paramRange(), MAX_GMOCK_PARAMS);

            // dfmt off
            param_chunks
                .save // don't modify the range
                .dropBackOne // separate last chunk to simply logic,
                             // all methods will thus return void
                .enumerate(1)
                .each!(a => genPart(a.index, a.value, m, code, delegate_mock));
            // dfmt on

            // if the mocked function returns a value it is simulated via the
            // "last part".
            genLastPart(param_chunks.length, param_chunks.back, m, code, delegate_mock);
        }

        if (m.paramRange().length <= MAX_GMOCK_PARAMS) {
            genMethodWithFewParams(m, hdr);
        } else {
            genMethodWithManyParams(m, hdr);
        }
    }

    auto ns = hdr.namespace(params.getMainNs().str);
    ns.suppressIndent(1);
    auto c = ns.class_("Mock" ~ in_c.name().str, "public " ~ in_c.name().str);
    auto pub = c.public_();
    pub.dtor(true, "Mock" ~ in_c.name().str)[$.end = " {}" ~ newline];

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
        auto m = CppMethod(m_.name, params, m_.returnType, CppAccess(AccessType.Public),
                CppConstMethod(m_.isConst), CppVirtualMethod(VirtualType.Pure));
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
