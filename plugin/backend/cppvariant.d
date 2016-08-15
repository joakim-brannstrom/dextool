// Written in the D programming language.
/**
Date: 2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Variant of C++ test double.
*/
module plugin.backend.cppvariant;

import std.typecons : Typedef, No, Flag;
import logger = std.experimental.logger;

import dsrcgen.cpp : CppModule, CppHModule;

import application.types;
import cpptooling.utility.nullvoid;
import cpptooling.analyzer.clang.ast.visitor : Visitor;

/** Control various aspectes of the analyze and generation like what nodes to
 * process.
 */
@safe interface Controller {
    /// Query the controller with the filename of the AST node for a decision
    /// if it shall be processed.
    bool doFile(in string filename, in string info);

    /** A list of includes for the test double header.
     *
     * Part of the controller because they are dynamic, may change depending on
     * for example calls to doFile.
     */
    FileName[] getIncludes();

    // TODO Move the doXXX to Parameters

    /// If any google mocks are generated.
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

/** Parameters used during generation.
 *
 * Important aspact that they do NOT change, therefore it is pure.
 */
@safe pure interface Parameters {
    import std.typecons : Tuple;

    alias Files = Tuple!(FileName, "hdr", FileName, "impl", FileName, "globals",
            FileName, "gmock", FileName, "pre_incl", FileName, "post_incl");

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
@safe interface Products {
    /** Data pushed from the generator to be written to files.
     *
     * The put value is the code generation tree. It allows the caller of
     * Generator to inject more data in the tree before writing. For example a
     * custom header.
     *
     * Params:
     *   fname = file the content is intended to be written to.
     *   hdr_data = data to write to the file.
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
    void putLocation(FileName loc, LocationType type);
}

/** Generator of test doubles for C++ code.
 */
struct Generator {
    import std.typecons : Typedef;

    import cpptooling.data.representation : CppRoot;
    import cpptooling.data.symbol.container : Container;
    import cpptooling.utility.conv : str;

    private static struct Modules {
        import plugin.utility : MakerInitializingClassMembers;

        mixin MakerInitializingClassMembers!Modules;

        CppModule hdr;
        CppModule impl;
        CppModule gmock;
    }

    ///
    this(Controller ctrl, Parameters params, Products products) {
        this.ctrl = ctrl;
        this.params = params;
        this.products = products;
    }

    /** Process structural data to a test double.
     *
     * raw -> filter -> translate -> code gen.
     *
     * Filters the structural data.
     * Controller is involved to allow filtering of identifiers according to
     * there lexical location.
     *
     * Translate prepares the data for code generator.
     * Extra structures needed for code generation is made at this stage.
     * On demand extra data is created. An example of on demand is --gmock.
     *
     * Code generation is a straight up translation.
     * Logical decisions should have been handled in earlier stages.
     */
    auto process(ref CppRoot root, ref Container container) {
        import cpptooling.data.symbol.types : USRType;

        auto fl = rawFilter(root, ctrl, products, (USRType usr) => container.find!LocationTag(usr));
        logger.trace("Filtered:\n", fl.toString());

        auto tr = translate(fl, container, ctrl, params);
        logger.trace("Translated to implementation:\n", tr.toString());

        auto modules = Modules.make();
        generate(tr, ctrl, params, modules, container);
        postProcess(ctrl, params, products, modules);
    }

private:
    Controller ctrl;
    Parameters params;
    Products products;

    static void postProcess(Controller ctrl, Parameters params, Products prods, Modules modules) {
        import cpptooling.generator.includes : convToIncludeGuard,
            generatetPreInclude, generatePostInclude;

        //TODO copied code from cstub. consider separating from this module to
        // allow reuse.
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

        prods.putFile(params.getFiles.hdr, outputHdr(modules.hdr, params.getFiles.hdr));
        prods.putFile(params.getFiles.impl, output(modules.impl, params.getFiles.hdr));

        if (ctrl.doPreIncludes) {
            prods.putFile(params.getFiles.pre_incl, generatetPreInclude(params.getFiles.pre_incl));
        }
        if (ctrl.doPostIncludes) {
            prods.putFile(params.getFiles.post_incl,
                    generatePostInclude(params.getFiles.post_incl));
        }

        if (ctrl.doGoogleMock) {
            import cpptooling.generator.gmock : generateGmockHdr;

            prods.putFile(params.getFiles.gmock, generateGmockHdr(params.getFiles.hdr,
                    params.getFiles.gmock, modules.gmock));
        }
    }
}

final class CppVisitor(RootT, ControllerT, ProductT) : Visitor {
    import std.typecons : scoped, NullableRef;

    import cpptooling.analyzer.clang.ast : UnexposedDecl, VarDecl, FunctionDecl,
        ClassDecl, Namespace, TranslationUnit;
    import cpptooling.analyzer.clang.ast.visitor : generateIndentIncrDecr;
    import cpptooling.analyzer.clang.analyze_helper : analyzeFunctionDecl,
        analyzeVarDecl;
    import cpptooling.data.representation : CppRoot, CxGlobalVariable;
    import cpptooling.data.type : CppNsStack, CxReturnType, CppNs,
        TypeKindVariable;
    import cpptooling.data.symbol.container : Container;
    import cpptooling.utility.clang : logNode, mixinNodeLog;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    RootT root;
    NullableRef!Container container;

    private {
        ControllerT ctrl;
        ProductT prod;
        CppNsStack ns_stack;
    }

    static if (is(RootT == CppRoot)) {
        // The container used is stored in the root.
        // All other visitors references the roots container.
        Container container_;

        this(ControllerT ctrl, ProductT prod) {
            this.ctrl = ctrl;
            this.prod = prod;
            this.root = CppRoot.make;
            this.container = &container_;
        }
    } else {
        this(ControllerT ctrl, ProductT prod, uint indent, CppNsStack ns_stack,
                NullableRef!Container container) {
            this.root = CppNamespace(ns_stack);
            this.ctrl = ctrl;
            this.prod = prod;
            this.indent = indent;
            this.ns_stack = ns_stack;
            this.container = container;
        }
    }

    override void visit(const(UnexposedDecl) v) {
        mixin(mixinNodeLog!());

        // An unexposed may be:

        // an extern "C"
        // UnexposedDecl "" extern "C" {...
        //   FunctionDecl "fun_c_linkage" void func_c_linkage
        v.accept(this);
    }

    override void visit(const(VarDecl) v) @trusted {
        import deimos.clang.index : CX_StorageClass;

        mixin(mixinNodeLog!());

        // TODO investigate if linkage() == CXLinkage_External should be used
        // instead.
        if (v.cursor.storageClass() == CX_StorageClass.CX_SC_Extern) {
            auto result = analyzeVarDecl(v, container, indent);
            auto var = CxGlobalVariable(result.instanceUSR,
                    TypeKindVariable(result.type, result.name));
            root.put(var);
        }
    }

    override void visit(const(FunctionDecl) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeFunctionDecl(v, container, indent);
        if (result.isValid) {
            auto func = CFunction(result.type.kind.usr, result.name, result.params,
                    CxReturnType(result.returnType), result.isVariadic, result.storageClass);
            root.put(func);
        }
    }

    override void visit(const(ClassDecl) v) @trusted {
        import std.typecons : scoped;
        import cpptooling.analyzer.clang.analyze_helper : ClassVisitor;
        import cpptooling.analyzer.clang.type : retrieveType;
        import cpptooling.analyzer.clang.utility : put;

        ///TODO add information if it is a public/protected/private class.
        ///TODO add metadata to the class if it is a definition or declaration

        mixin(mixinNodeLog!());
        logger.info("class: ", v.cursor.spelling);

        if (v.cursor.isDefinition) {
            auto visitor = scoped!ClassVisitor(v, ns_stack, container, indent + 1);
            v.accept(visitor);

            root.put(visitor.root);
            container.put(visitor.root, visitor.root.fullyQualifiedName);
        } else {
            auto type = retrieveType(v.cursor, container, indent);
            put(type, container, indent);
        }
    }

    override void visit(const(Namespace) v) @trusted {
        mixin(mixinNodeLog!());

        () @trusted{ ns_stack ~= CppNs(v.cursor.spelling); }();
        // pop the stack when done
        scope (exit)
            ns_stack = ns_stack[0 .. $ - 1];

        auto ns_visitor = scoped!(CppVisitor!(CppNamespace, ControllerT, ProductT))(ctrl,
                prod, indent, ns_stack, container);

        // fill the namespace with content from the analyse
        v.accept(ns_visitor);

        root.put(ns_visitor.root);
    }

    override void visit(const(TranslationUnit) v) {
        import std.algorithm : filter;
        import cpptooling.analyzer.clang.type : makeLocation;

        mixin(mixinNodeLog!());

        LocationTag tu_loc;
        () @trusted{ tu_loc = LocationTag(Location(v.cursor.spelling, 0, 0)); }();

        if (tu_loc.kind != LocationTag.Kind.noloc && ctrl.doFile(tu_loc.file,
                "root " ~ tu_loc.toString)) {
            prod.putLocation(FileName(tu_loc.file), LocationType.Root);
        }

        v.accept(this);
    }

    void toString(Writer)(scope Writer w) @safe const {
        import std.format : FormatSpec;
        import std.range.primitives : put;

        root.toString(w);
        put(w, "\n");

        auto fmt = FormatSpec!char("%s");
        container.get.toString(w, fmt);
    }

    override string toString() const {
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

import cpptooling.data.representation : CppRoot, CppClass, CppMethod, CppCtor,
    CppDtor, CFunction, CppNamespace;
import cpptooling.data.type : LocationTag, Location;
import cpptooling.data.symbol.container : Container;
import dsrcgen.cpp : E;

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

/** Structurally transform the input to a stub implementation.
 *
 * TODO should handle StorageClass like cvariant do.
 *
 * Ignoring C functions and globals by ignoring the root ranges funcRange and
 * globalRange.
 *
 * Params:
 *  ctrl: removes according to directives via ctrl
 */
CppT rawFilter(CppT, LookupT)(CppT input, Controller ctrl, Products prod, LookupT lookup) @safe {
    import std.algorithm : each, filter, map, filter;
    import std.range : tee;
    import application.types : FileName;
    import cpptooling.data.representation : dedup, StorageClass;
    import cpptooling.generator.utility : filterAnyLocation;

    // setup
    static if (is(CppT == CppRoot)) {
        auto filtered = CppRoot.make;
    } else static if (is(CppT == CppNamespace)) {
        auto filtered = CppNamespace.make(input.name);
        assert(!input.isAnonymous);
        assert(input.name.length > 0);
    } else {
        static assert("Type not supported: " ~ CppT.stringof);
    }

    // type specific
    static if (is(CppT == CppNamespace)) {
        // dfmt off
        input.funcRange
            .dedup
            // by definition static functions can't be replaced by test doubles
            .filter!(a => a.storageClass != StorageClass.Static)
            // ask controller if the file should be mocked, and thus the node
            .filterAnyLocation!(a => ctrl.doFile(a.location.file, cast(string) a.value.name ~ " " ~ a.location.toString))(lookup)
            // pass on location as a product to be used to calculate #include
            .tee!(a => prod.putLocation(FileName(a.location.file), LocationType.Leaf))
            .each!(a => filtered.put(a.value));
        // dfmt on
    }

    // Assuming that namespaces are never duplicated at this stage.
    // The assumption comes from the structure of the clang AST.

    // dfmt off
    input.namespaceRange
        .filter!(a => !a.isAnonymous)
        .map!(a => rawFilter(a, ctrl, prod, lookup))
        .each!(a => filtered.put(a));

    if (ctrl.doGoogleMock) {
        input.classRange
            // only classes with virtual functions are mocked
            .filter!(a => a.isVirtual)
            // ask controller (the user) if the file should be mocked
            .filterAnyLocation!(a => ctrl.doFile(a.location.file, cast(string) a.value.name ~ " " ~ a.location.toString))(lookup)
            // pass on location as a product to be used to calculate #include
            .tee!(a => prod.putLocation(FileName(a.location.file), LocationType.Leaf))
            // the class shall be further processed
            .each!(a => filtered.put(a.value));
    }
    // dfmt on

    return filtered;
}

CppRoot translate(CppRoot root, ref Container container, Controller ctrl, Parameters params) {
    import std.algorithm : map, filter, each;

    auto r = CppRoot.make;

    // dfmt off
    root.namespaceRange
        .map!(a => translate(a, container, ctrl, params))
        .filter!(a => !a.isNull)
        .each!(a => r.put(a.get));

    root.classRange
        .map!(a => mergeClassInherit(a, container))
        // can happen that the result is a class with no methods, thus in state Unknown
        .filter!(a => a.isVirtual)
        .each!((a) {a.setKind(ClassType.Gmock); r.put(a); });
    // dfmt on

    return r;
}

/** Translate namspaces and the content to test double implementations.
 */
NullableVoid!CppNamespace translate(CppNamespace input, ref Container container,
        Controller ctrl, Parameters params) {
    import std.algorithm : map, filter, each;
    import std.array : empty;
    import cpptooling.data.representation : CppNs;
    import cpptooling.generator.adapter : makeAdapter, makeSingleton;
    import cpptooling.generator.func : makeFuncInterface;
    import cpptooling.generator.gmock : makeGmock;

    static auto makeGmockInNs(CppClass c, Parameters params) {
        import cpptooling.data.representation : CppNs;

        auto ns = CppNamespace.make(CppNs(cast(string) params.getMainNs));
        ns.setKind(NamespaceType.TestDouble);
        ns.put(makeGmock!ClassType(c));
        return ns;
    }

    auto ns = CppNamespace.make(input.name);

    if (!input.funcRange.empty) {
        ns.put(makeSingleton!NamespaceType(params.getMainNs, params.getMainInterface));
        input.funcRange.each!(a => ns.put(a));

        auto td_ns = CppNamespace.make(CppNs(cast(string) params.getMainNs));
        td_ns.setKind(NamespaceType.TestDouble);

        auto i_free_func = makeFuncInterface(input.funcRange, params.getMainInterface);
        td_ns.put(i_free_func);
        td_ns.put(makeAdapter!(MainInterface, ClassType)(params.getMainInterface));

        if (ctrl.doGoogleMock) {
            td_ns.put(makeGmock!ClassType(i_free_func));
        }

        ns.put(td_ns);
    }

    //dfmt off
    input.namespaceRange()
        .map!(a => translate(a, container, ctrl, params))
        .filter!(a => !a.isNull)
        .each!(a => ns.put(a.get));

    input.classRange
        .map!(a => mergeClassInherit(a, container))
        // can happen that the result is a class with no methods, thus in state Unknown
        .filter!(a => a.isVirtual)
        .each!(a => ns.put(makeGmockInNs(a, params)));
    // dfmt on

    NullableVoid!CppNamespace rval;
    if (!ns.namespaceRange.empty || !ns.classRange.empty) {
        rval = ns;
    }

    return rval;
}

/** Translate the structure to code.
 *
 * order is important, affects code layout:
 *  - anonymouse for test double instance.
 *  - implementations using double.
 *  - adapter.
 */
void generate(CppRoot r, Controller ctrl, Parameters params,
        Generator.Modules modules, ref const(Container) container)
in {
    import std.array : empty;

    assert(r.funcRange.empty);
}
body {
    import std.algorithm : each, filter;
    import cpptooling.data.symbol.types : USRType;
    import cpptooling.generator.func : generateFuncImpl;
    import cpptooling.generator.gmock : generateGmock;
    import cpptooling.generator.includes : generateIncludes;
    import cpptooling.utility.conv : str;

    generateIncludes(ctrl, params, modules.hdr);

    static void gmockGlobal(T)(T r, CppModule gmock, Parameters params) {
        foreach (a; r.filter!(a => cast(ClassType) a.kind == ClassType.Gmock)) {
            generateGmock(a, gmock, params);
        }
    }

    // recursive to handle nested namespaces.
    // the singleton ns must be the first code generate or the impl can't
    // use the instance.
    static void eachNs(LookupT)(CppNamespace ns, Parameters params,
            Generator.Modules modules, CppModule impl_singleton, LookupT lookup) {

        auto inner = modules;
        CppModule inner_impl_singleton;

        final switch (cast(NamespaceType) ns.kind) with (NamespaceType) {
        case Normal:
            //TODO how to do this with meta-programming?
            inner.hdr = modules.hdr.namespace(ns.name.str);
            inner.hdr.suppressIndent(1);
            inner.impl = modules.impl.namespace(ns.name.str);
            inner.impl.suppressIndent(1);
            inner.gmock = modules.gmock.namespace(ns.name.str);
            inner.gmock.suppressIndent(1);
            inner_impl_singleton = inner.impl.base;
            inner_impl_singleton.suppressIndent(1);
            break;
        case TestDoubleSingleton:
            import cpptooling.generator.adapter : generateSingleton;

            generateSingleton(ns, impl_singleton);
            break;
        case TestDouble:
            generateNsTestDoubleHdr(ns, params, modules.hdr, modules.gmock, lookup);
            generateNsTestDoubleImpl(ns, modules.impl);
            break;
        }

        foreach (a; ns.funcRange) {
            generateFuncImpl(a, inner.impl);
        }
        foreach (a; ns.namespaceRange) {
            eachNs(a, params, inner, inner_impl_singleton, lookup);
        }
    }

    gmockGlobal(r.classRange, modules.gmock, params);
    // no singleton in global namespace thus null
    foreach (a; r.namespaceRange()) {
        eachNs(a, params, modules, null, (USRType usr) => container.find!LocationTag(usr));
    }
}

void generateClassHdr(LookupT)(CppClass c, CppModule hdr, CppModule gmock,
        Parameters params, LookupT lookup) {
    import cpptooling.generator.classes : generateHdr;
    import cpptooling.generator.gmock : generateGmock;

    final switch (cast(ClassType) c.kind()) {
    case ClassType.Normal:
    case ClassType.Adapter:
        generateHdr(c, hdr, No.locationAsComment, lookup);
        break;
    case ClassType.Gmock:
        generateGmock(c, gmock, params);
        break;
    }
}

void generateClassImpl(CppClass c, CppModule impl) {
    import cpptooling.generator.adapter : generateImplAdapter = generateImpl;

    final switch (cast(ClassType) c.kind()) {
    case ClassType.Normal:
        break;
    case ClassType.Adapter:
        generateImplAdapter(c, impl);
        break;
    case ClassType.Gmock:
        break;
    }
}

void generateNsTestDoubleHdr(LookupT)(CppNamespace ns, Parameters params,
        CppModule hdr, CppModule gmock, LookupT lookup) {
    import std.algorithm : each;
    import cpptooling.utility.conv : str;

    auto cpp_ns = hdr.namespace(ns.name.str);
    cpp_ns.suppressIndent(1);
    hdr.sep(2);

    foreach (a; ns.classRange()) {
        generateClassHdr(a, cpp_ns, gmock, params, lookup);
    }
}

void generateNsTestDoubleImpl(CppNamespace ns, CppModule impl) {
    import std.algorithm : each;
    import cpptooling.utility.conv : str;

    auto cpp_ns = impl.namespace(ns.name.str);
    cpp_ns.suppressIndent(1);
    impl.sep(2);

    ns.classRange().each!((a) { generateClassImpl(a, cpp_ns); });
}

CppClass mergeClassInherit(ref CppClass class_, ref Container container) {
    if (class_.inheritRange.length == 0) {
        return class_;
    }

    //TODO inefficient, lots of intermittent arrays and allocations.
    // Convert to a range based no-allocation.

    static bool isMethodOrOperator(T)(T method) @trusted {
        import std.variant : visit;
        import cpptooling.data.representation : CppMethod, CppMethodOp, CppCtor,
            CppDtor;

        // dfmt off
        return method.visit!((const CppMethod a) => true,
                        (const CppMethodOp a) => true,
                        (const CppCtor a) => false,
                        (const CppDtor a) => false);
        // dfmt on
    }

    static CppClass.CppFunc[] getMethods(const ref CppClass c, ref Container container) {
        import std.array : array, appender;
        import std.algorithm : copy, filter, map, each, cache;
        import std.range : chain;

        // dfmt off
        auto local_methods = c.methodRange
                .filter!(a => isMethodOrOperator(a));

        auto inherit_methods = c.inheritRange
            .map!(a => container.find!CppClass(a.fullyQualifiedName))
            // some classes do not exist in AST thus no methods returned
            .filter!(a => a.length > 0)
            .cache
            .map!(a => a.front)
            .map!(a => getMethods(a.get, container));
        // dfmt on

        auto methods = appender!(CppClass.CppFunc[])();
        () @trusted{ local_methods.copy(methods); inherit_methods.copy(methods); }();

        return methods.data;
    }

    static auto dedup(CppClass.CppFunc[] methods) {
        import std.algorithm : makeIndex, uniq, map;

        static auto getUniqeId(T)(ref T method) @trusted {
            import std.variant : visit;
            import cpptooling.data.representation : CppMethod, CppMethodOp,
                CppCtor, CppDtor;

            // dfmt off
            return method.visit!((CppMethod a) => a.id,
                                 (CppMethodOp a) => a.id,
                                 (CppCtor a) => a.id,
                                 (CppDtor a) => a.id);
            // dfmt on
        }

        return methods.uniq!((a, b) => getUniqeId(a) == getUniqeId(b));
    }

    auto methods = dedup(getMethods(class_, container));

    auto c = CppClass(class_.name, class_.inherits, class_.resideInNs);
    // dfmt off
    () @trusted {
        import std.algorithm : each;
        methods.each!(a => c.put(a));
    }();
    // dfmt on

    return c;
}
