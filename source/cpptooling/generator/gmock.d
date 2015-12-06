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
    import cpptooling.data.representation : VirtualType;

    assert(in_c.virtualType == VirtualType.Pure);
}
body {
    import std.algorithm : each;
    import std.conv : text;
    import std.format : format;
    import std.variant : visit;

    import cpptooling.data.representation;
    import cpptooling.utility.conv : str;

    static void ignore() {
    }

    static void genOp(CppMethodOp op, CppModule hdr) {
        logger.info("Found operator ", op.name);
    }

    static void genMethod(CppMethod m, CppModule hdr) {
        import cpptooling.data.representation : VirtualType;

        logger.errorf(m.paramRange().length > 10,
            "%s: Too many parameters in function to generate a correct google mock. Nr:%d",
            m.name, m.paramRange().length);

        string params = m.paramRange().joinParams();
        string name = m.name().str;
        string gmock_method = "MOCK_METHOD" ~ m.paramRange().length.text;
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
