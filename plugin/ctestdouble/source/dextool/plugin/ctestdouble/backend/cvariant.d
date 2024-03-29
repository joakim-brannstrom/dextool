/**
Date: 2015-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Generate a C test double implementation from data about the structural
representation.
*/
module dextool.plugin.ctestdouble.backend.cvariant;

import std.algorithm : filter, each, map, joiner;
import std.typecons : Flag, Yes, No;
import logger = std.experimental.logger;
import std.array : array, empty;

import dsrcgen.cpp : CppModule, CppHModule;
import my.sumtype;

import dextool.type : Path, DextoolVersion;
import cpptooling.data.symbol;
import libclang_ast.ast : Visitor;
import cpptooling.testdouble.header_filter : LocationType;
import cpptooling.type : MainName, StubPrefix, CustomHeader, MainNs, MainInterface;

/// Control various aspects of the analyze and generation like what nodes to
/// process.
@safe interface Controller {
    /// Query the controller with the filename of the AST node for a decision
    /// if it shall be processed.
    bool doFile(in string filename, in string info);

    /** Query the controller for a decision if it shall be processed. */
    bool doSymbol(string symbol);

    /** A list of includes for the test double header.
     *
     * Part of the controller because they are dynamic, may change depending on
     * for example calls to doFile.
     */
    Path[] getIncludes();

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

    /// Generate location of symbols as comments
    bool doLocationAsComment();
}

/// Parameters used during generation.
/// Important aspect that they do NOT change, therefore it is pure.
@safe pure interface Parameters {
    static struct Files {
        Path hdr;
        Path impl;
        Path globals;
        Path gmock;
        Path gmock_impl;
        Path pre_incl;
        Path post_incl;
    }

    /// Source files used to generate the test double.
    Path[] getIncludes();

    /// Output directory to store files in.
    Path getOutputDirectory();

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

    /// Dextool Tool version.
    DextoolVersion getToolVersion();

    /// Custom header to prepend generated files with.
    CustomHeader getCustomHeader();

    /** If an implementation of the interface for globals that zeroes them
     * shall be generated.
     */
    Flag!"generateZeroGlobals" generateZeroGlobals();
}

/// Data produced by the generator like files.
@safe interface Products {
    /** Data pushed from the test double generator to be written to files.
     *
     * The put value is the code generation tree. It allows the caller of
     * Generator to inject more data in the tree before writing. For
     * example a custom header.
     *
     * Params:
     *   fname = file the content is intended to be written to.
     *   hdr_data = data to write to the file.
     */
    void putFile(Path fname, CppHModule hdr_data);

    /// ditto.
    void putFile(Path fname, CppModule impl_data);

    /** During the translation phase the location of symbols that aren't
     * filtered out are pushed to the variant.
     *
     * It is intended that the variant control the #include directive strategy.
     * Just the files that was input?
     * Deduplicated list of files where the symbols was found?
     */
    void putLocation(Path loc, LocationType type);
}

/** Generator of test doubles for C code.
 */
struct Generator {
    import cpptooling.data : CppRoot;

    private static struct Modules {
        static Modules make() @safe {
            return Modules(new CppModule, new CppModule, new CppModule, new CppModule, new CppModule);
        }

        CppModule hdr;
        CppModule impl;
        CppModule globals;
        CppModule gmock;
        CppModule gmock_impl;
    }

    ///
    this(Controller ctrl, Parameters params, Products products) {
        this.ctrl = ctrl;
        this.params = params;
        this.products = products;
    }

    /** Filter and aggregate data for future processing.
     */
    void aggregate(ref CppRoot root, ref Container container) {
        import std.typecons : Nullable;
        import cpptooling.data.symbol.types : USRType;

        rawFilter(root, ctrl, products, filtered,
                (Nullable!USRType usr) => container.find!LocationTag(usr.get));
    }

    /** Process structural data to a test double.
     *
     * aggregated -> translate -> code generation.
     *
     * Translate analyzes what is left after filtering.
     * On demand extra data is created. An example of on demand is --gmock.
     *
     * Code generation is a straight up translation.
     * Logical decisions should have been handled in earlier stages.
     */
    void process(ref Container container) {
        logger.tracef("Filtered:\n%s\n", filtered.toString());

        auto implementation = makeImplementation(filtered, ctrl, params, container);
        logger.trace("Post processed:\n", implementation.toString());
        logger.tracef("kind: %s\nglobals: %s\nadapterKind: %s\n",
                implementation.kind, implementation.globals, implementation.adapterKind);

        auto m = Modules.make();
        generate(implementation, ctrl, params, container, m.hdr, m.impl,
                m.globals, m.gmock, m.gmock_impl);

        postProcess(m, ctrl, params, products);
    }

private:
    CppRoot filtered;
    Controller ctrl;
    Parameters params;
    Products products;

    static void postProcess(Modules modules, Controller ctrl, Parameters params, Products prod) {
        import cpptooling.generator.includes : convToIncludeGuard,
            generatePreInclude, generatePostInclude, makeHeader;

        /** Generate the C++ header file of the test double.
         * Params:
         *  fname = intended output filename, used for ifndef guard.
         */
        static auto outputHdr(CppModule hdr, Path fname, DextoolVersion ver,
                CustomHeader custom_hdr) {
            auto o = CppHModule(convToIncludeGuard(fname));
            o.header.append(makeHeader(fname, ver, custom_hdr));
            o.content.append(hdr);

            return o;
        }

        static auto output(CppModule code, Path incl_fname, Path dest,
                DextoolVersion ver, CustomHeader custom_hdr) {
            import std.path : baseName;

            auto o = new CppModule;
            o.suppressIndent(1);
            o.append(makeHeader(dest, ver, custom_hdr));
            o.include(incl_fname.baseName);
            o.sep(2);
            o.append(code);

            return o;
        }

        prod.putFile(params.getFiles.hdr, outputHdr(modules.hdr,
                params.getFiles.hdr, params.getToolVersion, params.getCustomHeader));
        prod.putFile(params.getFiles.impl, output(modules.impl,
                params.getFiles.hdr, params.getFiles.impl,
                params.getToolVersion, params.getCustomHeader));
        prod.putFile(params.getFiles.globals, output(modules.globals,
                params.getFiles.hdr, params.getFiles.globals,
                params.getToolVersion, params.getCustomHeader));

        if (ctrl.doPreIncludes) {
            prod.putFile(params.getFiles.pre_incl, generatePreInclude(params.getFiles.pre_incl));
        }
        if (ctrl.doPostIncludes) {
            prod.putFile(params.getFiles.post_incl, generatePostInclude(params.getFiles.post_incl));
        }

        //TODO refactor. should never reach this stage.
        if (ctrl.doGoogleMock) {
            import cpptooling.generator.gmock : generateGmockHdr, generateGmockImpl;

            prod.putFile(params.getFiles.gmock, generateGmockHdr(params.getFiles.hdr,
                    params.getFiles.gmock, params.getToolVersion,
                    params.getCustomHeader, modules.gmock));
            prod.putFile(params.getFiles.gmock_impl, generateGmockImpl(params.getFiles.gmock,
                    params.getFiles.gmock_impl, params.getToolVersion,
                    params.getCustomHeader, modules.gmock_impl));
        }
    }
}

final class CVisitor : Visitor {
    import std.typecons : scoped;

    import libclang_ast.ast : VarDecl, FunctionDecl, TranslationUnit, generateIndentIncrDecr;
    import cpptooling.analyzer.clang.analyze_helper : analyzeFunctionDecl, analyzeVarDecl;
    import cpptooling.data : CppRoot;
    import cpptooling.data.symbol : Container;
    import libclang_ast.cursor_logger : logNode, mixinNodeLog;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;

    CppRoot root;
    Container container;

    private {
        Controller ctrl;
        Products prod;
    }

    this(Controller ctrl, Products prod) {
        this.ctrl = ctrl;
        this.prod = prod;
    }

    void clearRoot() @safe {
        this.root = CppRoot.init;
    }

    override void visit(scope const VarDecl v) {
        import cpptooling.data : TypeKindVariable;
        import clang.c.Index : CX_StorageClass;

        mixin(mixinNodeLog!());

        //TODO ugly hack. Move this information to the representation. But for
        //now skipping all definitions
        if (v.cursor.storageClass() == CX_StorageClass.extern_) {
            auto result = analyzeVarDecl(v, container, indent);
            auto var = CxGlobalVariable(result.instanceUSR,
                    TypeKindVariable(result.type, result.name));
            root.put(var);
        }
    }

    override void visit(scope const FunctionDecl v) {
        import cpptooling.data.type : CxReturnType;

        mixin(mixinNodeLog!());

        auto result = analyzeFunctionDecl(v, container, indent);
        if (result.isValid) {
            auto func = CFunction(result.type.kind.usr, result.name, result.params,
                    CxReturnType(result.returnType), result.isVariadic, result.storageClass);
            root.put(func);
        }
    }

    override void visit(scope const TranslationUnit v) {
        import cpptooling.analyzer.clang.type : makeLocation;

        mixin(mixinNodeLog!());

        LocationTag tu_loc;
        () @trusted { tu_loc = LocationTag(Location(v.cursor.spelling, 0, 0)); }();

        if (tu_loc.kind != LocationTag.Kind.noloc && ctrl.doFile(tu_loc.file,
                "root " ~ tu_loc.toString)) {
            prod.putLocation(Path(tu_loc.file), LocationType.Root);
        }

        v.accept(this);
    }

    void toString(Writer)(scope Writer w) @safe {
        import std.format : FormatSpec;
        import std.range.primitives : put;

        auto fmt = FormatSpec!char("%u");
        fmt.writeUpToNextSpec(w);

        root.toString(w, fmt);
        put(w, "\n");
        container.toString(w, FormatSpec!char("%s"));
    }

    override string toString() {
        import std.exception : assumeUnique;

        char[] buf;
        buf.reserve(100);
        toString((const(char)[] s) { buf ~= s; });
        auto trustedUnique(T)(T t) @trusted {
            return assumeUnique(t);
        }

        return trustedUnique(buf);
    }
}

private:
@safe:

import cpptooling.data : CppRoot, CppClass, CppMethod, CppCtor, CppDtor,
    CFunction, CppNamespace, CxGlobalVariable, USRType, LocationTag, Location;
import dsrcgen.cpp : E, noIndent;

/** Contain data for code generation.
 */
struct ImplData {
    import cpptooling.data.type : CppMethodName;
    import dextool.plugin.ctestdouble.backend.adapter : AdapterKind;
    import dextool.plugin.ctestdouble.backend.global : MutableGlobal;

    CppRoot root;
    alias root this;

    /// Tagging of nodes in the root
    Kind[size_t] kind;
    /// Global, mutable variables
    MutableGlobal[] globals;
    /// Constructor kinds for ctors in an adapter
    AdapterKind[USRType] adapterKind;

    void tag(size_t id, Kind kind_) {
        kind[id] = kind_;
    }

    Kind lookup(size_t id) {
        if (auto k = id in kind) {
            return *k;
        }

        return Kind.none;
    }

    MutableGlobal lookupGlobal(CppMethodName name) {
        foreach (item; globals) {
            if (item.name == name) {
                return item;
            }
        }

        // Methods shall always be 1:1 mapped with the globals list.
        assert(0);
    }
}

enum Kind {
    none,
    /// Adapter class
    adapter,
    /// gmock class
    gmock,
    /// interface for globals
    initGlobalInterface,
    initGlobalsToZero,
    testDoubleNamespace,
    testDoubleSingleton,
    testDoubleInterface,
}

/** Structurally transformed the input to a test double implementation.
 *
 * This stage:
 *  - removes C++ code.
 *  - removes according to directives via ctrl.
 *
 * Params:
 *  input = structural representation of the source code
 *  ctrl = controll what nodes to keep
 *  prod = push location data of the nodes that are kept
 *  filtered = output structural representation
 *  lookup = callback function supporting lookup of locations
 */
void rawFilter(LookupT)(ref CppRoot input, Controller ctrl, Products prod,
        ref CppRoot filtered, LookupT lookup) {
    import std.range : tee;
    import cpptooling.data : StorageClass;
    import cpptooling.generator.utility : filterAnyLocation;

    // dfmt off
    input.funcRange
        .filter!(a => !a.usr.isNull)
        // by definition static functions can't be replaced by test doubles
        .filter!(a => a.storageClass != StorageClass.Static)
        // ask controller if the user wants to generate a test double function for the symbol.
        // note: using the fact that C do NOT have name mangling.
        .filter!(a => ctrl.doSymbol(a.name))
        // ask controller if to generate a test double for the function
        .filterAnyLocation!(a => ctrl.doFile(a.location.file, cast(string) a.value.name))(lookup)
        // pass on location as a product to be used to calculate #include
        .tee!(a => prod.putLocation(Path(a.location.file), LocationType.Leaf))
        .each!(a => filtered.put(a.value));

    input.globalRange()
        .filter!(a => !a.usr.isNull)
        // ask controller if the user wants to generate a global for the symbol.
        // note: using the fact that C do NOT have name mangling.
        .filter!(a => ctrl.doSymbol(a.name))
        // ask controller if to generate a test double for the function
        .filterAnyLocation!(a => ctrl.doFile(a.location.file, cast(string) a.value.name))(lookup)
        // pass on location as a product to be used to calculate #include
        .tee!(a => prod.putLocation(Path(a.location.file), LocationType.Leaf))
        .each!(a => filtered.put(a.value));
    // dfmt on
}

/** Transform the content of the root to a test double implementation root.
 *
 * Make an adapter.
 * Make a namespace holding the test double.
 * Make an interface for initialization of globals.
 * Make a google mock if asked by the user.
 */
auto makeImplementation(ref CppRoot root, Controller ctrl, Parameters params,
        ref Container container) @trusted {
    import cpptooling.data : CppNamespace, CppNs, CppClassName, CppInherit,
        CppAccess, AccessType, makeUniqueUSR, nextUniqueID, MergeMode;
    import cpptooling.generator.func : makeFuncInterface;
    import cpptooling.generator.gmock : makeGmock;
    import dextool.plugin.ctestdouble.backend.adapter : makeSingleton, makeAdapter;
    import dextool.plugin.ctestdouble.backend.global : makeGlobalInterface,
        makeZeroGlobal, filterMutable;

    ImplData impl;
    impl.root.merge(root, MergeMode.shallow);

    impl.globals = impl.globalRange.filterMutable(container).array;

    const has_mutable_globals = impl.globals.length != 0;
    const has_functions = !root.funcRange.empty;

    if (!has_functions && !has_mutable_globals) {
        return impl;
    }

    auto test_double_ns = CppNamespace.make(CppNs(params.getMainNs));

    if (has_functions) {
        auto singleton = makeSingleton(CppNs(params.getMainNs),
                CppClassName(params.getMainInterface), "test_double_inst");
        impl.kind[singleton.id] = Kind.testDoubleSingleton;
        impl.put(singleton); // (1)

        auto c_if = makeFuncInterface(impl.funcRange, CppClassName(params.getMainInterface));
        impl.tag(c_if.id, Kind.testDoubleInterface);
        test_double_ns.put(c_if);

        if (ctrl.doGoogleMock) {
            auto mock = makeGmock(c_if);
            impl.tag(mock.id, Kind.gmock);
            test_double_ns.put(mock);
        }
    }

    if (has_mutable_globals) {
        auto if_name = CppClassName(params.getMainInterface ~ "_InitGlobals");
        auto global_if = makeGlobalInterface(impl.globals[], if_name);
        impl.tag(global_if.id, Kind.initGlobalInterface);
        test_double_ns.put(global_if);

        if (params.generateZeroGlobals) {
            auto global_init_zero = makeZeroGlobal(impl.globals[],
                    CppClassName(params.getArtifactPrefix ~ "ZeroGlobals"),
                    params.getArtifactPrefix, CppInherit(if_name, CppAccess(AccessType.Public)));
            impl.tag(global_init_zero.id, Kind.initGlobalsToZero);
            test_double_ns.put(global_init_zero);
        }
    }

    // MUST be added after the singleton (1)
    impl.tag(test_double_ns.id, Kind.testDoubleNamespace);

    {
        // dfmt off
        auto adapter = makeAdapter(params.getMainInterface)
            .makeTestDouble(has_functions)
            .makeInitGlobals(has_mutable_globals)
            .makeZeroGlobals(params.generateZeroGlobals)
            .finalize(impl);
        impl.tag(adapter.id, Kind.adapter);
        test_double_ns.put(adapter);
        // dfmt on
    }

    impl.put(test_double_ns);
    return impl;
}

void generate(ref ImplData data, Controller ctrl, Parameters params, ref Container container,
        CppModule hdr, CppModule impl, CppModule globals, CppModule gmock, CppModule gmock_impl) {
    import cpptooling.data.symbol.types : USRType;
    import cpptooling.generator.func : generateFuncImpl;
    import cpptooling.generator.includes : generateWrapIncludeInExternC;
    import dextool.plugin.ctestdouble.backend.adapter : generateSingleton;

    generateWrapIncludeInExternC(ctrl, params, hdr);
    generateGlobal(data.globalRange, ctrl, params, container, globals);

    auto mutable_extern_hook = impl.base;
    mutable_extern_hook.suppressIndent(1);

    foreach (ns; data.namespaceRange) {
        switch (data.lookup(ns.id)) {
        case Kind.testDoubleSingleton:
            generateSingleton(ns, impl);
            break;
        case Kind.testDoubleNamespace:
            generateNsTestDoubleHdr(ns,
                    cast(Flag!"locationAsComment") ctrl.doLocationAsComment, params, hdr, gmock,
                    (USRType usr) => container.find!LocationTag(usr), (size_t id) => data.lookup(
                        id));
            generateNsTestDoubleImpl(ns, params, impl, gmock_impl,
                    mutable_extern_hook, data, params.getArtifactPrefix, container);
            break;

        default:
        }
    }

    // The generated functions must be extern C declared.
    auto extern_c = impl.suite("extern \"C\"");
    extern_c.suppressIndent(1);
    foreach (a; data.funcRange) {
        generateFuncImpl(a, extern_c);
    }
}

/// Generate the global definitions and macros for initialization.
void generateGlobal(RangeT)(RangeT r, Controller ctrl, Parameters params,
        ref Container container, CppModule globals) {
    import cpptooling.data : TypeKind, Void;

    void generateDefinitions(ref CxGlobalVariable global, Flag!"locationAsComment" loc_as_comment,
            string prefix, ref Container container, CppModule code)
    in {
        global.type.kind.info.match!(restrictTo!(TypeKind.CtorInfo, TypeKind.DtorInfo, (_) {
                assert(0, "wrong type");
            }), (_) {});
    }
    do {
        import std.format : format;
        import std.string : toUpper;

        string d_name = (prefix ~ "Init_").toUpper ~ global.name;

        if (loc_as_comment) {
            // dfmt off
            foreach (loc; container.find!LocationTag(global.usr.get)
                // both declaration and definition is OK
                .map!(a => a.any)
                .joiner) {
                code.comment("Origin " ~ loc.toString)[$.begin = "/// "];
            }
            // dfmt on
        }
        code.stmt(d_name);
    }

    void generatePreProcessor(ref CxGlobalVariable global, string prefix, CppModule code) {
        import std.string : toUpper;
        import cpptooling.data : toStringDecl;

        auto d_name = E((prefix ~ "Init_").toUpper ~ global.name);
        auto ifndef = code.IFNDEF(d_name);

        void handler() {
            ifndef.define(d_name ~ E(global.type.toStringDecl(global.name)));
        }

        // example: #define TEST_INIT_extern_a int extern_a[4]
        global.type.kind.info.match!(restrictTo!(TypeKind.ArrayInfo, TypeKind.FuncInfo,
                TypeKind.FuncPtrInfo, TypeKind.FuncSignatureInfo, TypeKind.PointerInfo, TypeKind.PrimitiveInfo,
                TypeKind.RecordInfo, TypeKind.SimpleInfo, TypeKind.TypeRefInfo, (a) {
                handler;
            }), restrictTo!(TypeKind.CtorInfo, TypeKind.DtorInfo, (a) {
                assert(0, "unexpected c++ code in preprocessor macros");
            }), (Void a) {
            logger.error("Type of global definition is null. Identifier ", global.name);
        });
    }

    auto global_macros = globals.base;
    global_macros.suppressIndent(1);
    globals.sep;
    auto global_definitions = globals.base;
    global_definitions.suppressIndent(1);

    foreach (a; r) {
        generatePreProcessor(a, params.getArtifactPrefix, global_macros);
        generateDefinitions(a, cast(Flag!"locationAsComment") ctrl.doLocationAsComment,
                params.getArtifactPrefix, container, global_definitions);
    }
}

void generateNsTestDoubleHdr(LookupT, KindLookupT)(ref CppNamespace ns, Flag!"locationAsComment" loc_as_comment,
        Parameters params, CppModule hdr, CppModule gmock, LookupT lookup, KindLookupT kind_lookup) {
    import cpptooling.generator.classes : generateHdr;
    import cpptooling.generator.gmock : generateGmock;

    auto test_double_ns = hdr.namespace(ns.name);
    test_double_ns.suppressIndent(1);
    hdr.sep(2);

    foreach (class_; ns.classRange()) {
        switch (kind_lookup(class_.id)) {
        case Kind.none:
        case Kind.initGlobalsToZero:
        case Kind.adapter:
            generateHdr(class_, test_double_ns, loc_as_comment, lookup);
            break;
        case Kind.initGlobalInterface:
        case Kind.testDoubleInterface:
            generateHdr(class_, test_double_ns, loc_as_comment, lookup, Yes.inlineDtor);
            break;
        case Kind.gmock:
            auto mock_ns = gmock.namespace(params.getMainNs).noIndent;
            generateGmock(class_, mock_ns, No.inlineCtorDtor);
            break;
        default:
        }
    }
}

void generateNsTestDoubleImpl(ref CppNamespace ns, Parameters params, CppModule impl, CppModule gmock_impl,
        CppModule mutable_extern_hook, ref ImplData data, StubPrefix prefix, ref Container container) {
    import dextool.plugin.ctestdouble.backend.global : generateGlobalExterns,
        generateInitGlobalsToZero;
    import dextool.plugin.ctestdouble.backend.adapter : generateClassImplAdapter = generateImpl;
    import cpptooling.generator.gmock : generateGmockImpl;

    auto test_double_ns = impl.namespace(ns.name);
    test_double_ns.suppressIndent(1);
    impl.sep(2);

    auto gmock_ns = gmock_impl.namespace(ns.name);
    gmock_ns.suppressIndent(1);
    gmock_ns.sep(2);

    auto lookup(USRType usr) {
        return usr in data.adapterKind;
    }

    foreach (class_; ns.classRange) {
        switch (data.lookup(class_.id)) {
        case Kind.adapter:
            generateClassImplAdapter(class_, data.globals,
                    prefix, test_double_ns, &lookup);
            break;

        case Kind.initGlobalsToZero:
            generateGlobalExterns(data.globals[],
                    mutable_extern_hook, container);
            generateInitGlobalsToZero(class_, test_double_ns, prefix, &data.lookupGlobal);
            break;

        case Kind.gmock:
            generateGmockImpl(class_, gmock_ns);
            break;

        default:
        }
    }
}
