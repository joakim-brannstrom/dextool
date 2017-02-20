/**
Copyright: Copyright (c) 2015-2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
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
void generateHdr(LookupT)(CppClass in_c, CppModule hdr, Flag!"locationAsComment" loc_as_comment,
        LookupT lookup, Flag!"inlineDtor" inline_dtor = No.inlineDtor) {
    import std.array : array;
    import std.algorithm : each, map, joiner;
    import std.variant : visit;
    import std.utf : toUTF8;
    import cpptooling.data.representation;
    import cpptooling.utility.sort : indexSort;

    static void genCtor(const ref CppCtor m, CppModule hdr) {
        string params = m.paramRange().joinParams();
        hdr.ctor(m.name, params);
    }

    static void genDtor(const ref CppDtor m, CppModule hdr, Flag!"inlineDtor" inline_dtor) {
        if (inline_dtor) {
            hdr.dtor(m.isVirtual() ? Yes.isVirtual : No.isVirtual, m.name)[$.end = " {}"];
        } else {
            hdr.dtor(m.isVirtual() ? Yes.isVirtual : No.isVirtual, m.name);
        }
    }

    static void genMethod(const ref CppMethod m, CppModule hdr,
            Flag!"locationAsComment" loc_as_comment, LookupT lookup) {
        import cpptooling.analyzer.type;

        if (loc_as_comment) {
            hdr.comment(genLocationComment(m.usr, lookup))[$.begin = "/// "];
        }

        foreach (comment; m.comments) {
            hdr.comment(comment)[$.begin = "/// "];
        }

        string params = m.paramRange().joinParams();
        auto o = hdr.method(cast(Flag!"isVirtual") m.isVirtual(),
                m.returnType.toStringDecl, m.name, cast(Flag!"isConst") m.isConst, params);
        if (m.isPure) {
            o[$.end = " = 0;"];
        }
    }

    //TODO not implemented
    static void genOp(const ref CppMethodOp m, CppModule hdr) {
    }

    in_c.commentRange().each!(a => hdr.comment(a)[$.begin = "/// "]);
    auto c = hdr.class_(in_c.name, in_c.inherits.map!(a => a.toString).joiner(", ").toUTF8);
    auto pub = c.public_();

    // dfmt off
    foreach (m; in_c.methodPublicRange
             .array()
             .indexSort!((ref a, ref b) => getName(a) < getName(b))
             ) {
        () @trusted {
        m.visit!(
            (const CppMethod m) => genMethod(m, pub, loc_as_comment, lookup),
            (const CppMethodOp m) => genOp(m, pub),
            (const CppCtor m) => genCtor(m, pub),
            (const CppDtor m) => genDtor(m, pub, inline_dtor));
        }();
    }
    // dfmt on
    hdr.sep(2);
}
