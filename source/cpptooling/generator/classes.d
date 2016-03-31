// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module cpptooling.generator.classes;

import std.typecons : Yes, No;

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
        hdr.dtor(m.isVirtual() ? Yes.isVirtual : No.isVirtual, m.name().str);
    }

    static void genMethod(CppMethod m, CppModule hdr) {
        string params = m.paramRange().joinParams();
        auto o = hdr.method(m.isVirtual() ? Yes.isVirtual : No.isVirtual,
                m.returnType().txt, m.name().str, m.isConst ? Yes.isConst : No.isConst, params);
        if (m.isPure) {
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
