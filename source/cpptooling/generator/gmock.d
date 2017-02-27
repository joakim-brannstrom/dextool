/**
Date: 2015-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Generate a google mock implementation of a C++ class with at least one virtual.
*/
module cpptooling.generator.gmock;

import std.ascii : newline;
import std.algorithm : joiner, map;
import std.conv : text;
import std.format : format;
import std.range : chain, only, retro, takeOne;
import std.typecons : Yes, No, Flag;
import std.variant : visit;

import logger = std.experimental.logger;

import dsrcgen.cpp : CppModule;

import dextool.type : DextoolVersion, CustomHeader;
import cpptooling.data.representation; // : CppClass, CppNamespace, CppMethodOp, CppMethod;
import cpptooling.analyzer.kind;
import cpptooling.analyzer.type;

@safe:

private string gmockMacro(size_t len, bool isConst)
in {
    assert(len <= 10);
}
body {
    if (isConst)
        return "MOCK_CONST_METHOD" ~ len.text;
    else
        return "MOCK_METHOD" ~ len.text;
}

private void ignore() {
}

private void genOp(const CppMethodOp m, CppModule hdr) {
    import cpptooling.data.representation : MemberVirtualType;

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

    static void genMockMethod(const CppMethodOp m, CppModule hdr) {
        string params = m.paramRange().joinParams();
        string gmock_name = translateOp(m.op);
        string gmock_macro = gmockMacro(m.paramRange().length, m.isConst);
        //TODO should use the toString function for TypeKind + TypeAttr, otherwise const isn't affecting it.
        string stmt = format("%s(%s, %s(%s))", gmock_macro, gmock_name,
                m.returnType.toStringDecl, params);
        hdr.stmt(stmt);
    }

    static void genMockCaller(const CppMethodOp m, CppModule hdr) {
        import dsrcgen.cpp : E;

        string gmock_name = translateOp(m.op);

        //TODO should use the toString function for TypeKind + TypeAttr, otherwise const isn't affecting it.
        CppModule code = hdr.method_inline(Yes.isVirtual, m.returnType.toStringDecl,
                m.name, m.isConst ? Yes.isConst : No.isConst, m.paramRange().joinParams());
        auto call = E(gmock_name)(m.paramRange().joinParamNames);

        if (m.returnType.toStringDecl == "void") {
            code.stmt(call);
        } else {
            code.return_(call);
        }
    }

    genMockMethod(m, hdr);
    genMockCaller(m, hdr);
}

private void genMethod(const CppMethod m, CppModule hdr) {
    enum MAX_GMOCK_PARAMS = 10;

    void genMethodWithFewParams(const CppMethod m, CppModule hdr) {
        hdr.stmt(format("%s(%s, %s(%s))", gmockMacro(m.paramRange().length,
                m.isConst), m.name, m.returnType.toStringDecl, m.paramRange().joinParams()));
        return;
    }

    void genMethodWithManyParams(const CppMethod m, CppModule hdr) {
        import std.range : chunks, enumerate, dropBackOne;

        static string partName(string name, size_t part_no) {
            return format("%s_MockPart%s", name, part_no);
        }

        static void genPart(T)(size_t part_no, T a, const CppMethod m,
                CppModule code, CppModule delegate_mock) {
            import dsrcgen.cpp : E;

            // dfmt off
            // inject gmock macro
            code.stmt(format("%s(%s, void(%s))",
                             gmockMacro(a.length, m.isConst),
                             partName(m.name, part_no),
                             a.joinParams));
            // inject delegation call to gmock macro
            delegate_mock.stmt(E(partName(m.name, part_no))(a.joinParamNames));
            // dfmt on
        }

        static void genLastPart(T)(size_t part_no, T p, const CppMethod m,
                CppModule code, CppModule delegate_mock) {
            import dsrcgen.cpp : E;

            auto part_name = partName(m.name, part_no);
            code.stmt(format("%s(%s, %s(%s))", gmockMacro(p.length, m.isConst),
                    part_name, m.returnType.toStringDecl, p.joinParams));

            auto stmt = E(part_name)(p.joinParamNames);

            if (m.returnType.toStringDecl == "void") {
                delegate_mock.stmt(stmt);
            } else {
                delegate_mock.return_(stmt);
            }
        }

        // Code block for gmock macros
        auto code = hdr.base();
        code.suppressIndent(1);

        // Generate mock method that delegates to partial mock methods
        auto delegate_mock = hdr.method_inline(Yes.isVirtual, m.returnType.toStringDecl,
                m.name, cast(Flag!"isConst") m.isConst, m.paramRange().joinParams());

        auto param_chunks = m.paramRange.chunks(MAX_GMOCK_PARAMS);

        // dfmt off
        foreach (a; param_chunks
                 .save // don't modify the range
                 .dropBackOne // separate last chunk to simply logic,
                 // all methods will thus return void
                 .enumerate(1)) {
            genPart(a.index, a.value, m, code, delegate_mock);
        }
        // dfmt on

        // if the mocked function returns a value it is simulated via the "last
        // part".
        genLastPart(param_chunks.length, param_chunks.back, m, code, delegate_mock);
    }

    if (m.paramRange().length <= MAX_GMOCK_PARAMS) {
        genMethodWithFewParams(m, hdr);
    } else {
        genMethodWithManyParams(m, hdr);
    }
}

/** Generate a Google Mock that implements in_c.
 *
 * Gmock has a restriction of max 10 parameters in a method. This gmock
 * generator has a work-around for the limitation by splitting the parameters
 * over many gmock functions. To fullfil the interface the generator then
 * generates an inlined function that in turn calls the gmocked functions.
 *
 * See test case class_interface_more_than_10_params.hpp.
 *
 * Params:
 *   ParamT Parameter type holding static information.
 *   in_c = Class to generate a mock implementation of.
 *   hdr = Header to generate the code in.
 *   params = tooling parameters that affects namespace the mock is generated in.
 */
void generateGmock(ParamT)(const CppClass in_c, CppModule hdr, ParamT params)
in {
    assert(in_c.isVirtual);
}
body {
    import cpptooling.data.representation;

    auto ns = hdr.namespace(params.getMainNs);
    ns.suppressIndent(1);
    // dfmt off
    // fully qualified class the mock inherit from
    auto base_class = "public " ~
        chain(
              // when joined ensure the qualifier start with "::"
              in_c.nsNestingRange.takeOne.map!(a => ""),
              in_c.nsNestingRange.retro.map!(a => a),
              only(cast(string) in_c.name))
        .joiner("::")
        .text;
    // dfmt on
    auto c = ns.class_("Mock" ~ in_c.name, base_class);
    auto pub = c.public_();
    pub.dtor(Yes.isVirtual, "Mock" ~ in_c.name)[$.end = " {}" ~ newline];

    foreach (m; in_c.methodRange()) {
        // dfmt off
        () @trusted {
        m.visit!((const CppMethod m) => genMethod(m, pub),
                 (const CppMethodOp m) => genOp(m, pub),
                 (const CppCtor m) => ignore(),
                 (const CppDtor m) => ignore());
        }();
        // dfmt on
    }
    hdr.sep(2);
}

auto generateGmockHdr(FileT)(FileT if_file, FileT incl_guard, DextoolVersion ver,
        CustomHeader custom_hdr, CppModule gmock) {
    import std.path : baseName;
    import dsrcgen.cpp : CppHModule;
    import cpptooling.generator.includes : convToIncludeGuard, makeHeader;

    auto o = CppHModule(convToIncludeGuard(incl_guard));
    o.header.append(makeHeader(incl_guard, ver, custom_hdr));
    o.content.include(((cast(string) if_file).baseName));
    o.content.include("gmock/gmock.h");
    o.content.sep(2);
    o.content.append(gmock);

    return o;
}

auto makeGmock(ClassT)(const CppClass c) {
    import std.array : array;
    import std.variant : visit;
    import cpptooling.data.representation;
    import cpptooling.utility.sort : indexSort;

    // Make all protected and private methods public to allow testing, for good
    // and bad. The policy can be changed. It is not set in stone. It is what I
    // thought was good at the time. If it creates problems in the future.
    // Identified use cases etc. Change it.
    static auto conv(T)(T m_) {
        import std.array : array;

        auto params = m_.paramRange.array();

        auto m = CppMethod(m_.usr, m_.name, params, m_.returnType, CppAccess(AccessType.Public),
                CppConstMethod(m_.isConst), CppVirtualMethod(MemberVirtualType.Pure));

        return m;
    }

    auto rclass = CppClass(c.name, c.inherits, c.resideInNs);
    rclass.setKind(ClassT.Gmock);

    //dfmt off
    foreach (m_in; c.methodRange
             .array()
             .indexSort!((ref a, ref b) => getName(a) < getName(b))
             ) {
        () @trusted{
            m_in.visit!((const CppMethod m) => m.isVirtual ? rclass.put(conv(m)) : false,
                        (const CppMethodOp m) => m.isVirtual ? rclass.put(conv(m)) : false,
                        (const CppCtor m) {},
                        (const CppDtor m) => m.isVirtual ? rclass.put(m) : false);
        }();
    }
    //dfmt on

    return rclass;
}
