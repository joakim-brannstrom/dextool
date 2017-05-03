/**
Date: 2016-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This file contains the backend for analyzing C++ code to generate a test
double.

Responsible for:
 - Analyze of the C++ code.
 - Transform the clang AST to data structures suitable for code generation.
 - Generate a C++ test double.
 - Error reporting to the frontend.
 - Provide an interface to the frontend for such data that a user can control.
    - What all the test doubles should be prefixed with.
    - Filename prefix.
    - To generate a gmock or not.
*/
module dextool.plugin.cpptestdouble.backend.cppvariant;

import std.typecons : No, Flag, Yes;
import logger = std.experimental.logger;

import dsrcgen.cpp : CppModule, CppHModule;

import dextool.type : FileName, DirName, MainName, StubPrefix, DextoolVersion,
    CustomHeader, MainNs, MainInterface;
import cpptooling.data.representation : CppNsStack;
import cpptooling.testdouble.header_filter : LocationType;

import dextool.plugin.cpptestdouble.backend.interface_;
import dextool.plugin.cpptestdouble.backend.visitor : AnalyzeData, CppTUVisitor;

/** Generator of test doubles for C++ code.
 *
 * Responsible for carrying data between processing steps.
 *
 * TODO postProcess shouldn't be a member method.
 */
struct Generator {
    import std.typecons : Nullable;
    import cpptooling.analyzer.clang.context : ClangContext;
    import cpptooling.data.representation : CppRoot;
    import cpptooling.data.symbol.container : Container;
    import dextool.type : ExitStatusType;

    private static struct Modules {
        import dextool.plugin.utility : MakerInitializingClassMembers;

        mixin MakerInitializingClassMembers!Modules;

        CppModule hdr;
        CppModule impl;
        CppModule gmock;
    }

    ///
    this(Controller ctrl, Parameters params, Products products) {
        this.analyze = AnalyzeData.make;
        this.ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
        this.ctrl = ctrl;
        this.params = params;
        this.products = products;
    }

    ExitStatusType analyzeFile(const string abs_in_file, const string[] use_cflags) {
        import std.typecons : NullableRef, scoped;
        import dextool.utility : analyzeFile;
        import cpptooling.data.representation : MergeMode;

        NullableRef!Container cont_ = &container;
        NullableRef!AnalyzeData analyz = &analyze.get();
        auto visitor = new CppTUVisitor(ctrl, products, analyz, cont_);

        if (analyzeFile(abs_in_file, use_cflags, visitor, ctx) == ExitStatusType.Errors) {
            return ExitStatusType.Errors;
        }

        debug logger.tracef("%u", visitor.root);

        auto fl = rawFilter(visitor.root, ctrl, products,
                (USRType usr) => container.find!LocationTag(usr));

        analyze.root.merge(fl, MergeMode.full);

        return ExitStatusType.Ok;
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
    void process() {
        import cpptooling.data.symbol.types : USRType;

        assert(!analyze.isNull);

        debug logger.trace(container.toString);

        logger.tracef("Filtered:\n%u", analyze.root);

        auto impl_data = ImplData.make();
        impl_data.putForLookup(analyze.classes);
        translate(analyze.root, container, ctrl, params, impl_data);
        analyze.nullify();

        logger.tracef("Translated to implementation:\n%u", impl_data.root);
        logger.trace("kind:\n", impl_data.kind);

        auto modules = Modules.make();
        generate(impl_data, ctrl, params, modules, container);
        postProcess(ctrl, params, products, modules);
    }

private:
    ClangContext ctx;
    Controller ctrl;
    Container container;
    Nullable!AnalyzeData analyze;
    Parameters params;
    Products products;

    static void postProcess(Controller ctrl, Parameters params, Products prods, Modules modules) {
        import cpptooling.generator.includes : convToIncludeGuard,
            generatetPreInclude, generatePostInclude, makeHeader;

        //TODO copied code from cstub. consider separating from this module to
        // allow reuse.
        static auto outputHdr(CppModule hdr, FileName fname, DextoolVersion ver,
                CustomHeader custom_hdr) {
            auto o = CppHModule(convToIncludeGuard(fname));
            o.header.append(makeHeader(fname, ver, custom_hdr));
            o.content.append(hdr);

            return o;
        }

        static auto output(CppModule code, FileName incl_fname, FileName dest,
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

        prods.putFile(params.getFiles.hdr, outputHdr(modules.hdr,
                params.getFiles.hdr, params.getToolVersion, params.getCustomHeader));
        prods.putFile(params.getFiles.impl, output(modules.impl,
                params.getFiles.hdr, params.getFiles.impl,
                params.getToolVersion, params.getCustomHeader));

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
                    params.getFiles.gmock, params.getToolVersion,
                    params.getCustomHeader, modules.gmock));
        }
    }
}

private:

@safe:

import cpptooling.data.representation : CppRoot, CppClass, CppMethod, CppCtor,
    CppDtor, CFunction, CppNamespace, USRType;
import cpptooling.data.type : LocationTag, Location;
import cpptooling.data.symbol.container : Container;
import dsrcgen.cpp : E;

enum Kind {
    none,
    /// Adapter class
    adapter,
    /// gmock class
    gmock,
    /// interface for globals
    testDoubleNamespace,
    testDoubleSingleton,
    testDoubleInterface,
}

struct ImplData {
    import cpptooling.data.type : CppMethodName;
    import cpptooling.data.symbol.types : FullyQualifiedNameType;

    CppRoot root;

    /// Tagging of nodes in the root determining how they are handled by the
    /// code generator step.
    private Kind[size_t] kind;
    /// Classes found during src analysis.
    private CppClass[FullyQualifiedNameType] classes;

    static auto make() {
        return ImplData(CppRoot.make);
    }

    /// Tag an ID with a kind.
    void tag(size_t id, Kind kind_) {
        kind[id] = kind_;
    }

    /// Lookup the tag for an ID.
    Kind lookup(size_t id) {
        if (auto k = id in kind) {
            return *k;
        }

        return Kind.none;
    }

    /// Copy an AA of classes.
    void putForLookup(ref CppClass[FullyQualifiedNameType] other) @trusted {
        foreach (v; other.byKeyValue) {
            classes[v.key] = v.value;
        }
    }

    /// Store a class that can later be retrieved via its FQN.
    void putForLookup(CppClass c) {
        classes[c.fullyQualifiedName] = c;
    }

    /// Returns: a range containing the class matching fqn, if found.
    auto lookupClass(FullyQualifiedNameType fqn) @safe {
        import std.range : only;
        import std.typecons : NullableRef;

        typeof(only(NullableRef!CppClass())) rval;
        if (auto c = fqn in classes) {
            rval = only(NullableRef!CppClass(c));
        }

        return rval;
    }
}

/** Filter the raw IR according to the users desire.
 *
 * TODO should handle StorageClass like cvariant do.
 *
 * Ignoring globals by ignoring the root ranges globalRange.
 *
 * Params:
 *  ctrl = removes according to directives via ctrl
 */
CppT rawFilter(CppT, LookupT)(CppT input, Controller ctrl, Products prod, LookupT lookup) @safe {
    import std.array : array;
    import std.algorithm : each, filter, map, filter;
    import std.range : tee;
    import dextool.type : FileName;
    import cpptooling.data.representation : StorageClass;
    import cpptooling.generator.utility : filterAnyLocation;

    // setup
    static if (is(CppT == CppRoot)) {
        auto filtered = CppRoot.make;
    } else static if (is(CppT == CppNamespace)) {
        auto filtered = CppNamespace(input.resideInNs);
        assert(!input.isAnonymous);
        assert(input.name.length > 0);
    } else {
        static assert("Type not supported: " ~ CppT.stringof);
    }

    if (ctrl.doFreeFunction) {
        // dfmt off
        input.funcRange
            // by definition static functions can't be replaced by test doubles
            .filter!(a => a.storageClass != StorageClass.Static)
            // ask controller if the file should be mocked, and thus the node
            .filterAnyLocation!(a => ctrl.doFile(a.location.file, cast(string) a.value.name ~ " " ~ a.location.toString))(lookup)
            // pass on location as a product to be used to calculate #include
            .tee!(a => prod.putLocation(FileName(a.location.file), LocationType.Leaf))
            .each!(a => filtered.put(a.value));
        // dfmt on
    }

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

/** Structurally transform the input to a test double implementation.
 *
 * In other words it the input IR (that has been filtered) is transformed to an
 * IR representing what code to generate.
 */
void translate(CppRoot root, ref Container container, Controller ctrl,
        Parameters params, ref ImplData impl) {
    import std.algorithm : map, filter, each;

    if (!root.funcRange.empty) {
        translateToTestDoubleForFreeFunctions(root, impl, cast(Flag!"doGoogleMock") ctrl.doGoogleMock,
                CppNsStack.init, params.getMainNs, params.getMainInterface, impl.root);
    }

    // dfmt off
    foreach (a; root.namespaceRange
        .map!(a => translate(a, impl, container, ctrl, params))
        .filter!(a => !a.empty)) {
        impl.root.put(a);
    }

    foreach (a; root.classRange
        .map!(a => mergeClassInherit(a, container, impl))
        // can happen that the result is a class with no methods, thus in state Unknown
        .filter!(a => a.isVirtual)) {
        impl.tag(a.id, Kind.gmock);
        impl.root.put(a);
        impl.putForLookup(a);
    }
    // dfmt on
}

/** Translate namspaces and the content to test double implementations.
 */
CppNamespace translate(CppNamespace input, ref ImplData data,
        ref Container container, Controller ctrl, Parameters params) {
    import std.algorithm : map, filter, each;
    import std.array : empty;
    import cpptooling.data.type : CppNsStack, CppNs;

    static auto makeGmockInNs(CppClass c, CppNsStack ns_hier, ref ImplData data) {
        import cpptooling.data.representation : CppNs;
        import cpptooling.generator.gmock : makeGmock;

        auto ns = CppNamespace(ns_hier);
        data.tag(ns.id, Kind.testDoubleNamespace);
        auto mock = makeGmock(c);
        data.tag(mock.id, Kind.gmock);
        ns.put(mock);
        return ns;
    }

    auto ns = CppNamespace(input.resideInNs);

    if (!input.funcRange.empty) {
        translateToTestDoubleForFreeFunctions(input, data, cast(Flag!"doGoogleMock") ctrl.doGoogleMock,
                ns.resideInNs, params.getMainNs, params.getMainInterface, ns);
    }

    //dfmt off
    input.namespaceRange()
        .map!(a => translate(a, data, container, ctrl, params))
        .filter!(a => !a.empty)
        .each!(a => ns.put(a));

    foreach (class_; input.classRange
        .map!(a => mergeClassInherit(a, container, data))
        // can happen that the result is a class with no methods, thus in state Unknown
        .filter!(a => a.isVirtual)) {
        auto mock = makeGmockInNs(class_, CppNsStack(ns.resideInNs.dup, CppNs(params.getMainNs)), data);
        ns.put(mock);
    }
    // dfmt on

    return ns;
}

void translateToTestDoubleForFreeFunctions(InT, OutT)(ref InT input, ref ImplData data,
        Flag!"doGoogleMock" do_gmock, const CppNsStack reside_in_ns,
        MainNs main_ns, MainInterface main_if, ref OutT ns) {
    import std.algorithm : each;
    import dextool.plugin.backend.cpptestdouble.adapter : makeAdapter,
        makeSingleton;
    import cpptooling.data.representation : CppNs, CppClassName;
    import cpptooling.generator.func : makeFuncInterface;
    import cpptooling.generator.gmock : makeGmock;

    // singleton instance must be before the functions
    auto singleton = makeSingleton(main_ns, main_if);
    data.tag(singleton.id, Kind.testDoubleSingleton);
    ns.put(singleton);

    // output the functions using the singleton
    input.funcRange.each!(a => ns.put(a));

    auto td_ns = CppNamespace(CppNsStack(reside_in_ns.dup, CppNs(main_ns)));
    data.tag(td_ns.id, Kind.testDoubleNamespace);

    auto i_free_func = makeFuncInterface(input.funcRange, CppClassName(main_if));
    data.tag(i_free_func.id, Kind.testDoubleInterface);
    td_ns.put(i_free_func);

    auto adapter = makeAdapter(main_if).makeTestDouble(true).finalize;
    data.tag(adapter.id, Kind.adapter);
    td_ns.put(adapter);

    if (do_gmock) {
        auto mock = makeGmock(i_free_func);
        data.tag(mock.id, Kind.gmock);
        td_ns.put(mock);
    }

    ns.put(td_ns);
}

/** Translate the structure to code.
 *
 * Generates:
 *  - #include's needed by the test double
 *  - recursive starting with the root:
 *    order is important, affects code layout:
 *      - anonymouse instance of the adapter for the test double
 *      - free function implementations using the registered test double
 *      - adapter registering a test double instance
 */
void generate(ref ImplData impl, Controller ctrl, Parameters params,
        Generator.Modules modules, ref const Container container) {
    import std.algorithm : filter;
    import cpptooling.generator.includes : generateIncludes;
    import cpptooling.generator.func : generateFuncImpl;
    import cpptooling.generator.gmock : generateGmock;

    generateIncludes(ctrl, params, modules.hdr);

    foreach (a; impl.root.classRange.filter!(a => impl.lookup(a.id) == Kind.gmock)) {
        generateGmock(a, modules.gmock, params);
    }

    auto td_singleton = modules.impl.base;
    td_singleton.suppressIndent(1);

    foreach (a; impl.root.funcRange) {
        generateFuncImpl(a, modules.impl);
    }

    // no singleton in global namespace thus null
    foreach (a; impl.root.namespaceRange()) {
        generateForEach(impl, a, params, modules, td_singleton, container);
    }
}

/**
 * recursive to handle nested namespaces.
 * the singleton ns must be the first code generate or the impl can't use the
 * instance.
 */
void generateForEach(ref ImplData impl, ref CppNamespace ns, Parameters params,
        Generator.Modules modules, CppModule impl_singleton, ref const Container container) {
    import cpptooling.data.symbol.types : USRType;
    import cpptooling.generator.func : generateFuncImpl;
    import cpptooling.generator.gmock : generateGmock;

    auto inner = modules;
    CppModule inner_impl_singleton;

    switch (impl.lookup(ns.id)) with (Kind) {
    case none:
        //TODO how to do this with meta-programming?
        inner.hdr = modules.hdr.namespace(ns.name);
        inner.hdr.suppressIndent(1);
        inner.impl = modules.impl.namespace(ns.name);
        inner.impl.suppressIndent(1);
        inner.gmock = modules.gmock.namespace(ns.name);
        inner.gmock.suppressIndent(1);
        inner_impl_singleton = inner.impl.base;
        inner_impl_singleton.suppressIndent(1);
        break;
    case testDoubleSingleton:
        import dextool.plugin.backend.cpptestdouble.adapter : generateSingleton;

        generateSingleton(ns, impl_singleton);
        break;
    case testDoubleInterface:
        break;
    case testDoubleNamespace:
        generateNsTestDoubleHdr(ns, params, modules.hdr, modules.gmock,
                (USRType usr) => container.find!LocationTag(usr), impl);
        generateNsTestDoubleImpl(ns, modules.impl, impl);
        break;
    default:
        break;
    }

    foreach (a; ns.funcRange) {
        generateFuncImpl(a, inner.impl);
    }

    foreach (a; ns.namespaceRange) {
        generateForEach(impl, a, params, inner, inner_impl_singleton, container);
    }
}

void generateNsTestDoubleHdr(LookupT)(CppNamespace ns, Parameters params,
        CppModule hdr, CppModule gmock, LookupT lookup, ref ImplData data) {
    import cpptooling.generator.classes : generateHdr;
    import cpptooling.generator.gmock : generateGmock;

    auto cpp_ns = hdr.namespace(ns.name);
    cpp_ns.suppressIndent(1);
    hdr.sep(2);

    foreach (c; ns.classRange()) {
        switch (data.lookup(c.id)) {
        case Kind.none:
            generateHdr(c, cpp_ns, No.locationAsComment, lookup, Yes.inlineDtor);
            break;
        case Kind.testDoubleInterface:
            generateHdr(c, cpp_ns,
                    No.locationAsComment, lookup, Yes.inlineDtor);
            break;
        case Kind.adapter:
            generateHdr(c, cpp_ns, No.locationAsComment, lookup);
            break;
        case Kind.gmock:
            generateGmock(c, gmock, params);
            break;
        default:
            break;
        }
    }
}

void generateNsTestDoubleImpl(CppNamespace ns, CppModule impl, ref ImplData data) {
    import std.algorithm : each;
    import dextool.plugin.backend.cpptestdouble.adapter : generateImpl;

    auto cpp_ns = impl.namespace(ns.name);
    cpp_ns.suppressIndent(1);
    impl.sep(2);

    foreach (ref class_; ns.classRange()) {
        switch (data.lookup(class_.id)) {
        case Kind.adapter:
            generateImpl(class_, cpp_ns);
            break;
        default:
            break;
        }
    }
}

CppClass mergeClassInherit(ref CppClass class_, ref Container container, ref ImplData impl) {
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

    static CppClass.CppFunc[] getMethods(const ref CppClass c,
            ref Container container, ref ImplData impl) @safe {
        import std.array : array, appender;
        import std.algorithm : cache, copy, each, filter, joiner, map;
        import std.range : chain;

        // dfmt off
        auto local_methods = c.methodRange
                .filter!(a => isMethodOrOperator(a));

        auto inherit_methods = c.inheritRange
            .map!(a => impl.lookupClass(a.fullyQualifiedName))
            // some classes do not exist in AST thus no methods returned
            .joiner
            .map!(a => getMethods(a, container, impl));
        // dfmt on

        auto methods = appender!(CppClass.CppFunc[])();
        () @trusted{ local_methods.copy(methods); inherit_methods.copy(methods); }();

        return methods.data;
    }

    //TODO this function is inefficient. So many allocations...
    static auto dedup(CppClass.CppFunc[] methods) @trusted {
        import std.array : array;
        import std.algorithm : makeIndex, uniq, map, sort;
        import cpptooling.utility.dedup : dedup;
        import cpptooling.data.representation : funcToString;

        static auto getUniqeId(T)(ref T method) {
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

        auto arr = methods.map!(a => getUniqeId(a)).array();

        auto index = new size_t[arr.length];
        // sorting the indexes
        makeIndex(arr, index);

        // dfmt off
        // contains a list of indexes into methods
        auto deduped_methods =
            index
            // dedup the sorted index
            .uniq!((a,b) => arr[a] == arr[b])
            .array();

        // deterministic sorting by function signature
        deduped_methods.sort!((a,b) { return methods[a].funcToString < methods[b].funcToString; });

        return deduped_methods
            // reconstruct an array from the sorted indexes
            .map!(a => methods[a])
            .array();
        // dfmt on
    }

    auto methods = dedup(getMethods(class_, container, impl));

    auto c = CppClass(class_.name, class_.inherits, class_.resideInNs);
    // dfmt off
    () @trusted {
        import std.algorithm : each;
        methods.each!(a => c.put(a));
    }();
    // dfmt on

    return c;
}
