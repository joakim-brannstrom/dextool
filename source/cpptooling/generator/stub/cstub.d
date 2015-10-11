/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// This program is free software; you can redistribute it and/or modify
/// it under the terms of the GNU General Public License as published by
/// the Free Software Foundation; either version 2 of the License, or
/// (at your option) any later version.
///
/// This program is distributed in the hope that it will be useful,
/// but WITHOUT ANY WARRANTY; without even the implied warranty of
/// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
/// GNU General Public License for more details.
///
/// You should have received a copy of the GNU General Public License
/// along with this program; if not, write to the Free Software
/// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
module cpptooling.generator.stub.cstub;

import std.typecons : Typedef;
import logger = std.experimental.logger;

import std.experimental.testing : name;

import dsrcgen.cpp : CppModule, CppHModule;

version (unittest) {
    import test.helpers : shouldEqualPretty;
    import std.experimental.testing : shouldEqual;
}

/** Prefix used for prepending generated code with a unique string to avoid
 * name collisions.
 * See specific functions for how it is used.
 */
alias StubPrefix = Typedef!(string, string.init, "StubPrefix");

alias FileName = Typedef!(string, string.init, "FileName");

/// Control variouse aspectes of the analyze and generation like what nodes to
/// process.
@safe interface StubController {
    /// Query the controller with the filename of the AST node for a decision
    /// if it shall be processed.
    bool doFile(in string filename);
}

/// Parameters used during generation.
/// Important aspact that they do NOT change, therefore it is pure.
@safe pure interface StubParameters {
    ///TODO remove this in the future. Use the filename from the root AST node or something.
    /// This is only kept here as a temporary solution.
    FileName getInputFile();

    ///TODO remove. Should be a parameter passed by the user or based on whatever replaces getInputFile().
    /// This is only kept here as a temporary solution.
    FileName getImplementationIncludeFile();

    ///TODO remove, a left over from the old design.
    FileName getOutputHdr();

    ///TODO remove, a left over from the old design.
    FileName getOutputImpl();

    /// Prefix to use for the generated files.
    /// Affects bothh the filename and the preprocessor #include.
    StubPrefix getFilePrefix();

    /// Prefix for the Manager of the test double.
    StubPrefix getManagerPrefix();
}

/// Data produced by the generator like files.
interface StubProducts {
    /** Data pushed from the stub generator to be written to files.
     *
     * The put value is the code generation tree. It allows the caller of
     * StubGenerator to inject more data in the tree before writing. For
     * example a custom header.
     *
     * Params:
     *   fname = file the content is intended to be written to.
     *   data = data to write to the file.
     */
    void putFile(FileName fname, CppHModule hdr_data);

    /// ditto.
    void putFile(FileName fname, CppModule impl_data);
}

struct StubGenerator {
    import std.typecons : Typedef;

    import cpptooling.data.representation : CppRoot;
    import cpptooling.utility.conv : str;

    this(StubController ctrl, StubParameters params, StubProducts products) {
        this.ctrl = ctrl;
        this.params = params;
        this.products = products;
    }

    /// Process structural data to a stub.
    auto process(CppRoot root) {
        logger.trace("Raw data:\n" ~ root.toString());
        auto tr = .translate(root, ctrl);

        // Does it have any C functions?
        if (!tr.funcRange().empty) {
            tr.put(makeCStubGlobal(params.getInputFile().str));
            auto c_if = makeCFuncInterface(tr.funcRange(), params.getInputFile.str);
            tr.put(c_if);
            tr.put(makeCFuncManager(params.getInputFile.str));
        }

        logger.trace("Post processed:\n" ~ tr.toString());

        auto hdr = new CppModule;
        auto impl = new CppModule;
        generateStub(tr, params.getInputFile().str, hdr, impl);
        postProcess(hdr, impl, params, products);
    }

private:
    static private void postProcess(CppModule hdr, CppModule impl,
        StubParameters params, StubProducts prod) {
        /** Generate the C++ header file of the stub.
         * Params:
         *  filename = intended output filename, used for ifdef guard.
         */
        static auto outputHdr(CppModule hdr, StubParameters params) {
            import std.string : translate;

            dchar[dchar] table = ['.' : '_', '-' : '_'];

            auto o = CppHModule(translate(params.getImplementationIncludeFile().str,
                table));
            o.content.include(params.getInputFile.str);
            o.content.sep(2);
            o.content.append(hdr);

            return o;
        }

        static auto outputImpl(CppModule impl, StubParameters params) {
            auto o = new CppModule;
            o.suppressIndent(1);
            o.include(params.getImplementationIncludeFile.str);
            o.sep(2);
            o.append(impl);

            return o;
        }

        prod.putFile(params.getOutputHdr, outputHdr(hdr, params));
        prod.putFile(params.getOutputImpl, outputImpl(impl, params));
    }

    StubController ctrl;
    StubParameters params;
    StubProducts products;
}

private:
@safe:

import cpptooling.data.representation : CppRoot, CppClass, CppMethod, CppCtor,
    CppDtor, CFunction, CppNamespace, CxLocation, CxGlobalVariable;
import dsrcgen.cpp : E;

enum dummyLoc = CxLocation("", -1, -1);

enum ClassType {
    Normal,
    Manager
}

enum NamespaceType {
    Normal,
    CStubGlobal
}

/// Convert the filename to the C prefix for interface, global etc.
string filenameToC(in string filename) {
    import std.algorithm : until;
    import std.uni : asCapitalized, isAlpha;
    import std.conv : text;

    // dfmt off
    return filename.asCapitalized
        .until!((a) => !isAlpha(a) && a != '_')
        .text;
    // dfmt on
}

/// Structurally transformed the input to a stub implementation.
/// This stage filter out uninteresting parts, like C++ or directives from ctrl.
/// No helper structs are generated at this stage.
CppRoot translate(CppRoot input, StubController ctrl) {
    import cpptooling.data.representation : dedup;

    CppRoot tr;

    foreach (f; input.funcRange().dedup) {
        auto r = translateCFunc(f, ctrl);
        if (!r.isNull) {
            tr.put(r.get);
        }
    }

    foreach (g; input.globalRange().dedup) {
        auto r = translateCGlobal(g, ctrl);
        if (!r.isNull) {
            tr.put(r.get);
        }
    }

    return tr;
}

auto translateCFunc(CFunction func, StubController ctrl) {
    import cpptooling.utility.nullvoid;

    NullableVoid!CFunction r;

    if (ctrl.doFile(func.location.file)) {
        r = func;
    }

    return r;
}

auto translateCGlobal(CxGlobalVariable g, StubController ctrl) {
    import cpptooling.utility.nullvoid;

    NullableVoid!CxGlobalVariable r;

    if (ctrl.doFile(g.location.file)) {
        r = g;
    }

    return r;
}

CppClass makeCFuncInterface(Tr)(Tr r, in string filename) {
    import cpptooling.data.representation;
    import cpptooling.utility.conv : str;

    import std.array : array;

    string c_name = filenameToC(filename);

    auto c = CppClass(CppClassName(c_name), CppClassInherit[].init);
    c.put(CppCtor(CppMethodName(c_name), CxParam[].init, CppAccess(AccessType.Public)));
    c.put(CppDtor(CppMethodName("~" ~ c_name), CppAccess(AccessType.Public),
        CppVirtualMethod(VirtualType.Yes)));

    foreach (f; r) {
        auto params = f.paramRange().array();
        if (f.isVariadic) {
            params = params[0 .. $ - 1];
        }

        auto name = CppMethodName(f.name.str);
        auto m = CppMethod(name, params, f.returnType(),
            CppAccess(AccessType.Public), CppConstMethod(false),
            CppVirtualMethod(VirtualType.Pure));

        c.put(m);
    }

    return c;
}

CppClass makeCFuncManager(in string filename) {
    import cpptooling.data.representation;
    import cpptooling.utility.conv : str;

    string c_if = filenameToC(filename);
    string c_name = c_if ~ "_Manager";

    auto c = CppClass(CppClassName(c_name), CppClassInherit[].init);
    c.setKind(ClassType.Manager);

    c.put(CppCtor(CppMethodName(c_name), CxParam[].init, CppAccess(AccessType.Public)));
    c.put(CppDtor(CppMethodName("~" ~ c_name), CppAccess(AccessType.Public),
        CppVirtualMethod(VirtualType.No)));

    c.put("Manage the shared memory area of the instance that fulfill the interface.");
    c.put("Connect inst to handle all stimuli.");
    auto param = makeCxParam(TypeKindVariable(makeTypeKind(c_if ~ "&",
        c_if ~ "&", false, true, false), CppVariable("inst")));
    auto rval = CxReturnType(makeTypeKind("void", "void", false, false, false));
    c.put(CppMethod(CppMethodName("Connect"), [param], rval,
        CppAccess(AccessType.Public), CppConstMethod(false), CppVirtualMethod(VirtualType.No)));

    return c;
}

CppNamespace makeCStubGlobal(string filename) {
    import cpptooling.data.representation : makeTypeKind, CppVariable,
        CxGlobalVariable;

    auto type = makeTypeKind(filenameToC(filename) ~ "*",
        filenameToC(filename) ~ "*", false, false, true);
    auto v = CxGlobalVariable(type, CppVariable("stub_inst"), dummyLoc);
    auto ns = CppNamespace.makeAnonymous();
    ns.setKind(NamespaceType.CStubGlobal);
    ns.put(v);

    return ns;
}

void generateStub(CppRoot r, in string filename, CppModule hdr, CppModule impl) {
    import std.algorithm : each, filter;
    import cpptooling.utility.conv : str;

    auto globalR = r.globalRange();
    if (!globalR.empty) {
        auto ifdef_hdr = hdr.IFDEF("DEFINE_GLOBAL_" ~ filenameToC(filename));
        globalR.each!((a) { generateCGlobalHdr(a, ifdef_hdr); });
    }

    r.namespaceRange().filter!(a => a.kind() == NamespaceType.CStubGlobal).each!((a) {
        generateCStubGlobal(a, impl);
    });

    r.funcRange().each!((a) { generateCFuncImpl(a, impl); });
    r.classRange().each!((a) {
        generateClassHdr(a, hdr);
        generateClassImpl(a, impl);
    });
}

void generateCGlobalHdr(CxGlobalVariable g, CppModule hdr) {
    import cpptooling.utility.conv : str;

    hdr.stmt(E(g.type.toString) ~ E(g.name.str));
}

///TODO print the function prototype and location it was found at.
void generateCFuncImpl(CFunction f, CppModule impl) {
    import cpptooling.data.representation;
    import cpptooling.utility.conv : str;

    string params = joinParams(f.paramRange());
    string names = joinParamNames(f.paramRange());

    with (impl.func_body(f.returnType().toString, f.name().str, params)) {
        if (f.returnType().toString == "void") {
            stmt(E("stub_inst->" ~ f.name().str)(E(names)));
        } else {
            return_(E("stub_inst->" ~ f.name().str)(E(names)));
        }
    }
    impl.sep(2);
}

void generateClassHdr(CppClass in_c, CppModule hdr) {
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
        auto o = hdr.method(m.isVirtual(), m.returnType().toString,
            m.name().str, m.isConst(), params);
        if (m.virtualType() == VirtualType.Pure) {
            o[$.end = " = 0;"];
        }
    }

    in_c.commentRange().each!(a => hdr.comment(a)[$.begin = "/// "]);
    auto c = hdr.class_(in_c.name().str);
    auto pub = c.public_();

    with (pub) {
        foreach (m; in_c.methodPublicRange()) {
            // dfmt off
            () @trusted {
            m.visit!((CppMethod m) => genMethod(m, pub),
                     (CppCtor m) => genCtor(m, pub),
                     (CppDtor m) => genDtor(m, pub));
            }();
            // dfmt on
        }
    }
    hdr.sep(2);
}

void generateClassImpl(CppClass c, CppModule impl) {
    final switch (cast(ClassType) c.kind()) {
    case ClassType.Normal:
        break;
    case ClassType.Manager:
        generateClassImplManager(c, impl);
        break;
    }
}

/// Expecting only three functions. c'tor, d'tor and Connect.
void generateClassImplManager(CppClass c, CppModule impl) {
    import std.variant : visit;
    import cpptooling.data.representation;

    static void genCtor(CppClass c, CppCtor m, CppModule impl) {
        with (impl.ctor_body(m.name.str)) {
            stmt(E("stub_inst") = E("0"));
        }
        impl.sep(2);
    }

    static void genDtor(CppClass c, CppDtor m, CppModule impl) {
        with (impl.dtor_body(c.name.str)) {
            stmt(E("stub_inst") = E("0"));
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
            stmt(E("stub_inst") = E("&" ~ p));
        }
        impl.sep(2);
    }

    impl.sep(2);

    foreach (m; c.methodPublicRange()) {
        () @trusted{
            m.visit!((CppMethod m) => genMethod(c, m, impl),
                (CppCtor m) => genCtor(c, m, impl), (CppDtor m) => genDtor(c, m, impl));
        }();
    }
}

void generateCStubGlobal(CppNamespace in_ns, CppModule impl) {
    import std.ascii : newline;
    import cpptooling.utility.conv : str;

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

@name("should stop on dot when generating C prefix")
unittest {
    string fname = "some_file.hpp";
    shouldEqual(filenameToC(fname), "Some_file");

    fname = "some_file_fun";
    shouldEqual(filenameToC(fname), "Some_file_fun");
}
