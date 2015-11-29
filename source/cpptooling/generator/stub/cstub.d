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

import application.types;

version (unittest) {
    import test.helpers : shouldEqualPretty;
    import std.experimental.testing : shouldEqual;
}

/// Control variouse aspectes of the analyze and generation like what nodes to
/// process.
@safe interface StubController {
    /// Query the controller with the filename of the AST node for a decision
    /// if it shall be processed.
    bool doFile(in string filename);

    /** A list of includes for the test double header.
     *
     * Part of the controller because they are dynamic, may change depending on
     * for example calls to doFile.
     */
    FileName[] getIncludes();

    /// Controls generation of google mock.
    bool doGoogleMock();

    /// Generate a pre_include header file from internal template?
    bool doPreIncludes();

    /// Generate a #include of the pre include header
    bool doIncludeOfPreIncludes();

    /// Generate a post_include header file from internal template?
    bool doPostIncludes();

    /// Generate a #include of the post include header
    bool doIncludeOfPostIncludes();
}

/// Parameters used during generation.
/// Important aspact that they do NOT change, therefore it is pure.
@safe pure interface StubParameters {
    import std.typecons : Tuple;

    alias Files = Tuple!(FileName, "hdr", FileName, "impl", FileName,
        "globals", FileName, "gmock", FileName, "pre_incl", FileName, "post_incl");

    /// Source files used to generate the stub.
    FileName[] getIncludes();

    /// Output directory to store files in.
    DirName getOutputDirectory();

    /// Files to write generated test double data to.
    Files getFiles();

    /// Holds the interface for the test double, used in Adaptor.
    MainInterface getMainInterface();

    /// Prefix to use for the generated files.
    /// Affects both the filename and the preprocessor #include.
    StubPrefix getFilePrefix();

    /// Prefix used for test artifacts.
    StubPrefix getArtifactPrefix();
}

/// Data produced by the generator like files.
@safe interface StubProducts {
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

    /** During the translation phase the location of symbols that aren't
     * filtered out are pushed to the variant.
     *
     * It is intended that the variant control the #include directive strategy.
     * Just the files that was input?
     * Deduplicated list of files where the symbols was found?
     */
    void putLocation(FileName loc);
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

    /** Process structural data to a test double.
     *
     * translate -> intermediate -> code generation.
     *
     * translate filters the structural data.
     * Controller is involved to allow filtering of identifiers in files.
     *
     * Intermediate analyzes what is left after filtering.
     * On demand extra data is created.
     *
     * Code generation is a straight up translation.
     * Logical decisions should have been handled in earlier stages.
     *
     * TODO refactor the control flow. Especially the gmock part.
     */
    auto process(CppRoot root) {
        logger.trace("Raw data:\n" ~ root.toString());
        auto tr = .translate(root, ctrl, products);

        // Does it have any C functions?
        if (!tr.funcRange().empty) {
            tr.put(makeCStubGlobal(params.getMainInterface));
            auto c_if = makeCFuncInterface(tr.funcRange(), params.getMainInterface);
            tr.put(c_if);
            if (ctrl.doGoogleMock) {
                // could reuse.. don't.
                auto mock = c_if;
                mock.setKind(ClassType.Gmock);
                tr.put(mock);
            }
            tr.put(makeTestDoubleAdapter(params.getMainInterface));
        }

        logger.trace("Post processed:\n" ~ tr.toString());

        auto hdr = new CppModule;
        auto impl = new CppModule;
        auto globals = new CppModule;
        auto gmock = new CppModule;
        generateStub(tr, ctrl, params, hdr, impl, globals, gmock);
        postProcess(hdr, impl, globals, gmock, ctrl, params, products);
    }

private:
    static private void postProcess(CppModule hdr, CppModule impl,
        CppModule globals, CppModule gmock, StubController ctrl,
        StubParameters params, StubProducts prod) {

        static string makeIncludeGuard(FileName fname) {
            import std.string : translate;
            import std.path : baseName;

            // dfmt off
            dchar[dchar] table = [
                '.' : '_',
                '-' : '_',
                '/' : '_'];
            // dfmt on

            return translate(fname.str.baseName, table);
        }

        /** Generate the C++ header file of the stub.
         * Params:
         *  filename = intended output filename, used for ifndef guard.
         */
        static auto outputHdr(CppModule hdr, FileName fname) {
            auto o = CppHModule(makeIncludeGuard(fname));
            o.content.append(hdr);

            return o;
        }

        static auto output(CppModule code, FileName incl_fname) {
            import std.path : baseName;

            auto o = new CppModule;
            o.suppressIndent(1);
            o.include(incl_fname.str.baseName);
            o.sep(2);
            o.append(code);

            return o;
        }

        static auto outputPreIncludes(FileName fname) {
            auto o = CppHModule(makeIncludeGuard(fname));
            auto c = new CppModule;
            c.stmt("#undef __cplusplus")[$.end = ""];
            o.content.append(c);

            return o;
        }

        static auto outputPostIncludes(FileName fname) {
            auto o = CppHModule(makeIncludeGuard(fname));
            auto c = new CppModule;
            c.define("__cplusplus");
            o.content.append(c);

            return o;
        }

        prod.putFile(params.getFiles.hdr, outputHdr(hdr, params.getFiles.hdr));
        prod.putFile(params.getFiles.impl, output(impl, params.getFiles.hdr));
        prod.putFile(params.getFiles.globals, output(globals, params.getFiles.hdr));

        if (ctrl.doPreIncludes) {
            prod.putFile(params.getFiles.pre_incl, outputPreIncludes(params.getFiles.pre_incl));
        }
        if (ctrl.doPostIncludes) {
            prod.putFile(params.getFiles.post_incl, outputPostIncludes(params.getFiles.post_incl));
        }

        //TODO refactor. should never reach this stage.
        if (ctrl.doGoogleMock) {
            prod.putFile(params.getFiles.gmock, outputHdr(gmock, params.getFiles.gmock));
        }
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

enum dummyLoc = CxLocation("<test double>", 0, 0);

enum ClassType {
    Normal,
    Adaptor,
    Gmock
}

enum NamespaceType {
    Normal,
    CStubGlobal
}

/** Structurally transformed the input to a stub implementation.
 *
 * This stage:
 *  - removes C++ code.
 *  - removes according to directives via ctrl.
 *  - produces file locations for declarations of variables and functions.
 */
CppRoot translate(CppRoot input, StubController ctrl, StubProducts prod) {
    import cpptooling.data.representation : dedup;

    CppRoot tr;

    foreach (f; input.funcRange().dedup) {
        auto r = translateCFunc(f, ctrl, prod);
        if (!r.isNull) {
            tr.put(r.get);
        }
    }

    foreach (g; input.globalRange().dedup) {
        auto r = translateCGlobal(g, ctrl, prod);
        if (!r.isNull) {
            tr.put(r.get);
        }
    }

    return tr;
}

auto translateCFunc(CFunction func, StubController ctrl, StubProducts prod) {
    import cpptooling.utility.nullvoid;

    NullableVoid!CFunction r;

    if (ctrl.doFile(func.location.file)) {
        r = func;
        prod.putLocation(FileName(func.location.file));
    } else {
        logger.info("Ignoring function: ", func.toString);
    }

    return r;
}

auto translateCGlobal(CxGlobalVariable g, StubController ctrl, StubProducts prod) {
    import cpptooling.utility.nullvoid;

    NullableVoid!CxGlobalVariable r;

    if (ctrl.doFile(g.location.file)) {
        r = g;
        prod.putLocation(FileName(g.location.file));
    } else {
        logger.info("Ignoring global variable: ", g.toString);
    }

    return r;
}

///TODO change filename from generic type string to FileName.
CppClass makeCFuncInterface(Tr)(Tr r, in MainInterface main_if) {
    import cpptooling.data.representation;
    import cpptooling.utility.conv : str;

    import std.array : array;

    string c_name = cast(string) main_if;

    auto c = CppClass(CppClassName(c_name), CppClassInherit[].init);

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

CppClass makeTestDoubleAdapter(MainInterface main_if) {
    import cpptooling.data.representation;
    import cpptooling.utility.conv : str;

    string c_if = main_if.str;
    string c_name = "Adaptor";

    auto c = CppClass(CppClassName(c_name), CppClassInherit[].init);
    c.setKind(ClassType.Adaptor);

    auto param = makeCxParam(TypeKindVariable(makeTypeKind(c_if ~ "&", false,
        true, false), CppVariable("inst")));

    c.put("Adaptor connecting the C implementation with interface.");
    c.put("The lifetime of the connection is the same as the instance of the adaptor.");

    c.put(CppCtor(CppMethodName(c_name), [param], CppAccess(AccessType.Public)));
    c.put(CppDtor(CppMethodName("~" ~ c_name), CppAccess(AccessType.Public),
        CppVirtualMethod(VirtualType.No)));

    return c;
}

/// make an anonymous namespace containing a ptr to an instance of a test
/// double that implement the interface needed.
CppNamespace makeCStubGlobal(MainInterface main_if) {
    import cpptooling.data.representation : makeTypeKind, CppVariable,
        CxGlobalVariable;

    auto type = makeTypeKind(cast(string) main_if ~ "*", false, false, true);
    auto v = CxGlobalVariable(type, CppVariable("test_double_inst"), dummyLoc);
    auto ns = CppNamespace.makeAnonymous();
    ns.setKind(NamespaceType.CStubGlobal);
    ns.put(v);

    return ns;
}

void generateStub(CppRoot r, StubController ctrl, StubParameters params,
    CppModule hdr, CppModule impl, CppModule globals, CppModule gmock) {
    import std.algorithm : each, filter;
    import cpptooling.utility.conv : str;

    generateCIncludes(ctrl, params, hdr);

    auto globalR = r.globalRange();
    if (!globalR.empty) {
        globalR.each!((a) {
            generateCGlobalDefine(a, params.getArtifactPrefix.str, globals);
        });
        globals.sep(2);

        globalR = r.globalRange();
        globalR.each!((a) {
            generateCGlobalDefinition(a, params.getArtifactPrefix.str, globals);
        });
    }

    r.namespaceRange().filter!(a => a.kind() == NamespaceType.CStubGlobal).each!((a) {
        generateCStubGlobal(a, impl);
    });

    // The generated functions must be extern C declared.
    auto extern_c = impl.suite("extern \"C\"");
    extern_c.suppressIndent(1);
    r.funcRange().each!((a) { generateCFuncImpl(a, extern_c); });

    r.classRange().each!((a) {
        generateClassHdr(a, hdr, gmock, params);
        generateClassImpl(a, impl);
    });
}

void generateCGlobalDefine(CxGlobalVariable g, string prefix, CppModule code) {
    import std.string : toUpper;
    import cpptooling.utility.conv : str;
    import cpptooling.analyzer.type : TypeKind;

    auto d_name = (prefix ~ "Init_").toUpper ~ g.name.str;
    auto ifndef = code.IFNDEF(d_name);

    final switch (g.type.info.kind) with (TypeKind.Info) {
    case Kind.simple:
        ifndef.define(E(d_name) ~ E(g.name.str));
        break;
    case Kind.array:
        ifndef.define(E(d_name) ~ E(g.name.str ~ g.type.info.indexes));
        break;
    case Kind.funcPtr:
        ifndef.define(E(d_name));
        break;
    case Kind.null_:
        logger.error("Type of global definition is null. Identifier ", g.name.str);
        break;
    }
}

void generateCGlobalDefinition(CxGlobalVariable g, string prefix, CppModule code) {
    import std.format : format;
    import std.string : toUpper;
    import cpptooling.utility.conv : str;
    import cpptooling.analyzer.type : TypeKind;

    auto d_name = (prefix ~ "Init_").toUpper ~ g.name.str;

    string txt;
    final switch (g.type.info.kind) with (TypeKind.Info) {
    case Kind.simple:
        txt = E(g.type.toString) ~ E(d_name);
        break;
    case Kind.array:
        txt = E(g.type.info.elementType) ~ E(d_name);
        break;
    case Kind.funcPtr:
        txt = E(format(g.type.info.fmt, g.name.str)) ~ E(d_name);
        break;
    case Kind.null_:
        logger.error("Type of global definition is null. Identifier ", g.name.str);
        break;
    }

    code.stmt(txt);
}

/// Generates a C implementation calling the test double via the matching
/// interface.
void generateCFuncImpl(CFunction f, CppModule impl) {
    import cpptooling.data.representation;
    import cpptooling.utility.conv : str;

    // assuming that a function declaration void a() in C is meant to be void
    // a(void), not variadic.
    string params;
    auto p_range = f.paramRange();
    if (p_range.length == 1 && !f.isVariadic || p_range.length > 1) {
        params = joinParams(p_range);
    }
    string names = joinParamNames(f.paramRange());

    with (impl.func_body(f.returnType().toString, f.name().str, params)) {
        if (f.returnType().toString == "void") {
            stmt(E("test_double_inst->" ~ f.name().str)(E(names)));
        } else {
            return_(E("test_double_inst->" ~ f.name().str)(E(names)));
        }
    }
    impl.sep(2);
}

void generateClassHdr(CppClass c, CppModule hdr, CppModule gmock, StubParameters params) {
    final switch (cast(ClassType) c.kind()) {
    case ClassType.Normal:
    case ClassType.Adaptor:
        generateClassHdrNormal(c, hdr);
        break;
    case ClassType.Gmock:
        generateClassHdrGmock(c, gmock, params);
    }
}

void generateClassHdrNormal(CppClass in_c, CppModule hdr) {
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

/// Assuming that in_c is pure virtual. Therefor the logic is simpler.
/// TODO add support for const functions.
void generateClassHdrGmock(CppClass in_c, CppModule hdr, StubParameters params)
in {
    import cpptooling.data.representation : VirtualType;

    assert(in_c.virtualType == VirtualType.Pure);
}
body {
    import std.algorithm : each;
    import std.conv : text;
    import std.format : format;
    import std.path : baseName;
    import std.variant : visit;

    import cpptooling.data.representation;
    import cpptooling.utility.conv : str;

    static void genCtor(CppCtor m, CppModule hdr) {
    }

    static void genDtor(CppDtor m, CppModule hdr) {
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

    hdr.include(params.getFiles.hdr.str.baseName);
    hdr.include("gmock/gmock.h");
    hdr.sep(2);

    auto c = hdr.class_(in_c.name().str ~ "_Mock", "public " ~ in_c.name().str);
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
    case ClassType.Adaptor:
        generateClassImplAdaptor(c, impl);
        break;
    case ClassType.Gmock:
        break;
    }
}

/// Expecting only three functions. c'tor, d'tor and Connect.
void generateClassImplAdaptor(CppClass c, CppModule impl) {
    import std.variant : visit;
    import cpptooling.data.representation;
    import cpptooling.utility.conv : str;

    // C'tor is expected to have one parameter.
    static void genCtor(CppClass c, CppCtor m, CppModule impl) {
        // dfmt off
        TypeKindVariable p0 = () @trusted {
            return m.paramRange().front.visit!(
                (TypeKindVariable tkv) => tkv,
                (TypeKind tk) => TypeKindVariable(tk, CppVariable("inst")),
                (VariadicType vt) {
                    logger.error("Variadic c'tor not supported:", m.toString);
                    return TypeKindVariable(makeTypeKind("not supported", false,
                        false, false), CppVariable("not supported"));
                })();
        }();
        // dfmt on

        with (impl.ctor_body(m.name.str, E(p0.type.toString) ~ E(p0.name.str))) {
            stmt(E("test_double_inst") = E("&" ~ p0.name.str));
        }
        impl.sep(2);
    }

    static void genDtor(CppClass c, CppDtor m, CppModule impl) {
        with (impl.dtor_body(c.name.str)) {
            stmt("test_double_inst = 0");
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
            stmt(E("test_double_inst") = E("&" ~ p));
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

void generateCIncludes(StubController ctrl, StubParameters params, CppModule hdr) {
    import std.path : baseName;
    import cpptooling.utility.conv : str;

    if (ctrl.doIncludeOfPreIncludes) {
        hdr.include(params.getFiles.pre_incl.str.baseName);
    }

    auto extern_c = hdr.suite("extern \"C\"");
    extern_c.suppressIndent(1);

    foreach (incl; params.getIncludes) {
        extern_c.include(cast(string) incl);
    }

    if (ctrl.doIncludeOfPostIncludes) {
        hdr.include(params.getFiles.post_incl.str.baseName);
    }

    hdr.sep(2);
}
