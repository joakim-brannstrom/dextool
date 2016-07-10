// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module cpptooling.generator.classes;

import std.typecons : Yes, No, Flag;

import dsrcgen.cpp : CppModule;

import cpptooling.data.representation : CppClass;

@safe:

private void genComment(T)(T m, CppModule hdr, Flag!"locationAsComment" loc_as_comment) {
    import std.format : format;
    import cpptooling.data.type : LocationTag, Location;

    if (loc_as_comment && m.location.kind == LocationTag.Kind.loc) {
        hdr.comment("Origin " ~ m.location.toString)[$.begin = "/// "];
    }
}

/// Generate code for a C++ class from a CppClass specification.
void generateHdr(CppClass in_c, CppModule hdr, Flag!"locationAsComment" loc_as_comment) {
    import std.algorithm : each;
    import std.variant : visit;
    import cpptooling.data.representation;
    import cpptooling.utility.conv : str;

    static void genCtor(const ref CppCtor m, CppModule hdr) {
        string params = m.paramRange().joinParams();
        hdr.ctor(m.name().str, params);
    }

    static void genDtor(const ref CppDtor m, CppModule hdr) {
        hdr.dtor(m.isVirtual() ? Yes.isVirtual : No.isVirtual, m.name().str);
    }

    static void genMethod(const ref CppMethod m, CppModule hdr,
            Flag!"locationAsComment" loc_as_comment) {
        import cpptooling.analyzer.type;

        m.genComment(hdr, loc_as_comment);

        string params = m.paramRange().joinParams();
        auto o = hdr.method(cast(Flag!"isVirtual") m.isVirtual(),
                m.returnType.toStringDecl, m.name().str, cast(Flag!"isConst") m.isConst, params);
        if (m.isPure) {
            o[$.end = " = 0;"];
        }
    }

    //TODO not implemented
    static void genOp(const ref CppMethodOp m, CppModule hdr) {
    }

    in_c.commentRange().each!(a => hdr.comment(a)[$.begin = "/// "]);
    auto c = hdr.class_(in_c.name().str);
    auto pub = c.public_();

    foreach (m; in_c.methodPublicRange()) {
        // dfmt off
        () @trusted {
        m.visit!(
            (const CppMethod m) => genMethod(m, pub, loc_as_comment),
            (const CppMethodOp m) => genOp(m, pub),
            (const CppCtor m) => genCtor(m, pub),
            (const CppDtor m) => genDtor(m, pub));
        }();
        // dfmt on
    }
    hdr.sep(2);
}
