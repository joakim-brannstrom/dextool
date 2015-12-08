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
module cpptooling.generator.classes;

import dsrcgen.cpp : CppModule;

import cpptooling.data.representation : CppClass;

@safe:

/// Generate code for a C++ class from a CppClass specification.
void generateHdr(CppClass in_c, CppModule hdr) {
    import std.algorithm : each;
    import std.variant : visit;
    import cpptooling.data.representation;
    import cpptooling.utility.conv : str;

    static void genCtor(CppCtor m, CppModule hdr) {
        string params = m.paramRange().joinParams();
        hdr.ctor(m.name().str, params);
    }

    static void genDtor(CppDtor m, CppModule hdr) {
        hdr.dtor(m.isVirtual(), m.name().str);
    }

    static void genMethod(CppMethod m, CppModule hdr) {
        import cpptooling.data.representation : VirtualType;

        string params = m.paramRange().joinParams();
        auto o = hdr.method(m.isVirtual(), m.returnType().txt, m.name().str, m.isConst(),
            params);
        if (m.virtualType() == VirtualType.Pure) {
            o[$.end = " = 0;"];
        }
    }

    //TODO not implemented
    static void genOp(CppMethodOp m, CppModule hdr) {
    }

    in_c.commentRange().each!(a => hdr.comment(a)[$.begin = "/// "]);
    auto c = hdr.class_(in_c.name().str);
    auto pub = c.public_();

    foreach (m; in_c.methodPublicRange()) {
        // dfmt off
        () @trusted {
        m.visit!((CppMethod m) => genMethod(m, pub),
                 (CppMethodOp m) => genOp(m, pub),
                 (CppCtor m) => genCtor(m, pub),
                 (CppDtor m) => genDtor(m, pub));
        }();
        // dfmt on
    }
    hdr.sep(2);
}
