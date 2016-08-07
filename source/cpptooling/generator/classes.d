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
import cpptooling.data.type : LocationTag;
import cpptooling.data.symbol.types : USRType;

@safe:

// for now this function is only used at one place but genCtor, genDtor and
// genOp is expected to use it in the future.
private string genLocationComment(LookupT)(USRType usr, LookupT lookup) {
    import std.algorithm : map, joiner;

    foreach (loc; lookup(usr).map!(a => a.any).joiner) {
        return "Origin " ~ loc.toString;
    }

    return "Unknown origin for USR " ~ cast(string) usr;
}

/** Generate code for a C++ class from a CppClass specification.
 *
 * Params:
 *  lookup = expecting same signature and behavior as Container.find!LocationTag
 */
void generateHdr(LookupT)(CppClass in_c, CppModule hdr,
        Flag!"locationAsComment" loc_as_comment, LookupT lookup) {
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
            Flag!"locationAsComment" loc_as_comment, LookupT lookup) {
        import cpptooling.analyzer.type;

        if (loc_as_comment) {
            hdr.comment(genLocationComment(m.usr, lookup))[$.begin = "/// "];
        }

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
            (const CppMethod m) => genMethod(m, pub, loc_as_comment, lookup),
            (const CppMethodOp m) => genOp(m, pub),
            (const CppCtor m) => genCtor(m, pub),
            (const CppDtor m) => genDtor(m, pub));
        }();
        // dfmt on
    }
    hdr.sep(2);
}
