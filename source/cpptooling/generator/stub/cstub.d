/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// Generate a C test double implementation from data about the structural
/// representation.
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

    /// Name affecting interface, namespace and output file.
    MainName getMainName();

    /** Namespace for the generated test double.
     *
     * Contains the adapter, C++ interface, gmock etc.
     */
    MainNs getMainNs();

    /** Name of the interface of the test double.
     *
     * Used in Adapter.
     */
    MainInterface getMainInterface();

    /** Prefix to use for the generated files.
     *
     * Affects both the filename and the preprocessor #include.
     */
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
        import cpptooling.data.representation : CppNamespace, CppNs;

        logger.trace("Raw data:\n" ~ root.toString());
        auto tr = .translate(root, ctrl, products);

        // Does it have any C functions?
        if (!tr.funcRange().empty) {
            tr.put(makeCStubGlobal(params.getMainNs, params.getMainInterface));

            auto ns = CppNamespace.make(CppNs(params.getMainNs.str));
            ns.setKind(NamespaceType.TestDouble);

            auto c_if = makeCFuncInterface(tr.funcRange(), params.getMainInterface);

            ns.put(c_if);
            if (ctrl.doGoogleMock) {
                // could reuse.. don't.
                auto mock = c_if;
                mock.setKind(ClassType.Gmock);
                ns.put(mock);
            }
            ns.put(makeTestDoubleAdapter(params.getMainInterface));
            tr.put(ns);
        }

        logger.trace("Post processed:\n" ~ tr.toString());

        auto hdr = new CppModule;
        auto impl = new CppModule;
        auto globals = new CppModule;
        auto gmock = new CppModule;
        generate(tr, ctrl, params, hdr, impl, globals, gmock);
        postProcess(hdr, impl, globals, gmock, ctrl, params, products);
    }

private:
    static private void postProcess(CppModule hdr, CppModule impl,
        CppModule globals, CppModule gmock, StubController ctrl,
        StubParameters params, StubProducts prod) {
        import cpptooling.generator.includes : convToIncludeGuard,
            generatetPreInclude, generatePostInclude;

        /** Generate the C++ header file of the stub.
         * Params:
         *  filename = intended output filename, used for ifndef guard.
         */
        static auto outputHdr(CppModule hdr, FileName fname) {
            auto o = CppHModule(convToIncludeGuard(fname));
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

        prod.putFile(params.getFiles.hdr, outputHdr(hdr, params.getFiles.hdr));
        prod.putFile(params.getFiles.impl, output(impl, params.getFiles.hdr));
        prod.putFile(params.getFiles.globals, output(globals, params.getFiles.hdr));

        if (ctrl.doPreIncludes) {
            prod.putFile(params.getFiles.pre_incl, generatetPreInclude(params.getFiles.pre_incl));
        }
        if (ctrl.doPostIncludes) {
            prod.putFile(params.getFiles.post_incl, generatePostInclude(params.getFiles.post_incl));
        }

        //TODO refactor. should never reach this stage.
        if (ctrl.doGoogleMock) {
            import cpptooling.generator.gmock : generateGmockHdr;

            prod.putFile(params.getFiles.gmock,
                generateGmockHdr(params.getFiles.hdr, params.getFiles.gmock, gmock));
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
    Adapter,
    Gmock
}

enum NamespaceType {
    Normal,
    TestDoubleSingleton,
    TestDouble
}

/** Structurally transformed the input to a stub implementation.
 *
 * This stage:
 *  - removes C++ code.
 *  - removes according to directives via ctrl.
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

static import cpptooling.generator.func;

alias translateCFunc = cpptooling.generator.func.rawFilter!(StubController, StubProducts);

alias generateCFuncImpl = cpptooling.generator.func.generateFuncImpl;

alias makeCFuncInterface = cpptooling.generator.func.makeFuncInterface;

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

static import cpptooling.generator.adapter;

alias makeTestDoubleAdapter = cpptooling.generator.adapter.makeAdapter!(MainInterface,
    ClassType);

alias makeCStubGlobal = cpptooling.generator.adapter.makeSingleton!NamespaceType;

void generate(CppRoot r, StubController ctrl, StubParameters params, CppModule hdr,
    CppModule impl, CppModule globals, CppModule gmock) {
    import std.algorithm : each;
    import cpptooling.utility.conv : str;

    generateCIncludes(ctrl, params, hdr);

    auto globalR = r.globalRange();
    if (!globalR.empty) {
        globalR.each!((a) {
            generateCGlobalPreProcessorDefine(a, params.getArtifactPrefix.str, globals);
        });
        globals.sep(2);

        globalR = r.globalRange();
        globalR.each!((a) {
            generateCGlobalDefinition(a, params.getArtifactPrefix.str, globals);
        });
    }

    static void eachNs(CppNamespace ns, StubParameters params, CppModule hdr,
        CppModule impl, CppModule gmock) {
        final switch (cast(NamespaceType) ns.kind) {
        case NamespaceType.Normal:
            break;
        case NamespaceType.TestDoubleSingleton:
            generateTestDoubleSingleton(ns, impl);
            break;
        case NamespaceType.TestDouble:
            generateNsTestDoubleHdr(ns, params, hdr, gmock);
            generateNsTestDoubleImpl(ns, params, impl);
            break;
        }
    }

    r.namespaceRange().each!(a => eachNs(a, params, hdr, impl, gmock));

    // The generated functions must be extern C declared.
    auto extern_c = impl.suite("extern \"C\"");
    extern_c.suppressIndent(1);
    r.funcRange().each!((a) { generateCFuncImpl(a, extern_c); });
}

void generateCGlobalPreProcessorDefine(CxGlobalVariable g, string prefix, CppModule code) {
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

void generateClassHdr(CppClass c, CppModule hdr, CppModule gmock, StubParameters params) {
    final switch (cast(ClassType) c.kind()) {
    case ClassType.Normal:
    case ClassType.Adapter:
        generateClassHdrNormal(c, hdr);
        break;
    case ClassType.Gmock:
        generateClassHdrGmock(c, gmock, params);
        break;
    }
}

import cpptooling.generator.classes : generateClassHdrNormal = generateHdr;

static import cpptooling.generator.gmock;

alias generateClassHdrGmock = cpptooling.generator.gmock.generateGmock!StubParameters;

import cpptooling.generator.adapter : generateClassImplAdapter = generateImpl;

void generateClassImpl(CppClass c, CppModule impl) {
    final switch (cast(ClassType) c.kind()) {
    case ClassType.Normal:
        break;
    case ClassType.Adapter:
        generateClassImplAdapter(c, impl);
        break;
    case ClassType.Gmock:
        break;
    }
}

import cpptooling.generator.adapter : generateTestDoubleSingleton = generateSingleton;

static import cpptooling.generator.includes;

alias generateCIncludes = cpptooling.generator.includes.generateC!(StubController,
    StubParameters);

void generateNsTestDoubleHdr(CppNamespace ns, StubParameters params, CppModule hdr,
    CppModule gmock) {
    import std.algorithm : each;
    import cpptooling.utility.conv : str;

    auto cpp_ns = hdr.namespace(ns.name.str);
    cpp_ns.suppressIndent(1);
    hdr.sep(2);

    ns.classRange().each!((a) { generateClassHdr(a, cpp_ns, gmock, params); });
}

void generateNsTestDoubleImpl(CppNamespace ns, StubParameters params, CppModule impl) {
    import std.algorithm : each;
    import cpptooling.utility.conv : str;

    auto cpp_ns = impl.namespace(ns.name.str);
    cpp_ns.suppressIndent(1);
    impl.sep(2);

    ns.classRange().each!((a) { generateClassImpl(a, cpp_ns); });
}
