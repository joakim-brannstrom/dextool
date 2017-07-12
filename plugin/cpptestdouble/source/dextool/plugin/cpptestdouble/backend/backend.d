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
module dextool.plugin.cpptestdouble.backend.backend;

import std.typecons : Flag, Yes;
import logger = std.experimental.logger;

import dsrcgen.cpp : CppModule, CppHModule;

import dextool.type : AbsolutePath, CustomHeader, DextoolVersion, FileName,
    MainInterface, MainNs, WriteStrategy;
import cpptooling.data.representation : CppNsStack;
import cpptooling.testdouble.header_filter : LocationType;

import dextool.plugin.cpptestdouble.backend.generate_cpp : generate;
import dextool.plugin.cpptestdouble.backend.interface_ : Controller, Parameters,
    Products, Transform;
import dextool.plugin.cpptestdouble.backend.type : Code, GeneratedData,
    ImplData, IncludeHooks, Kind;
import dextool.plugin.cpptestdouble.backend.visitor : AnalyzeData, CppTUVisitor;

/** Backend of test doubles for C++ code.
 *
 * Responsible for carrying data between processing steps.
 *
 * TODO postProcess shouldn't be a member method.
 */
struct Backend {
    import std.typecons : Nullable;
    import cpptooling.analyzer.clang.context : ClangContext;
    import cpptooling.data.representation : CppRoot;
    import cpptooling.data.symbol.container : Container;
    import dextool.type : ExitStatusType;

    ///
    this(Controller ctrl, Parameters params, Products products, Transform transform) {
        this.analyze = AnalyzeData.make;
        this.ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
        this.ctrl = ctrl;
        this.params = params;
        this.products = products;
        this.transform = transform;
    }

    ExitStatusType analyzeFile(const AbsolutePath abs_in_file, const string[] use_cflags) {
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
        impl_data.includeHooks = IncludeHooks.make(transform);

        impl_data.putForLookup(analyze.classes);
        translate(analyze.root, container, ctrl, params, impl_data);
        analyze.nullify();

        logger.tracef("Translated to implementation:\n%u", impl_data.root);
        logger.trace("kind:\n", impl_data.kind);

        GeneratedData gen_data;
        gen_data.includeHooks = impl_data.includeHooks;
        generate(impl_data, ctrl, params, gen_data, container);
        postProcess(ctrl, params, products, transform, gen_data);
    }

private:
    ClangContext ctx;
    Controller ctrl;
    Container container;
    Nullable!AnalyzeData analyze;
    Parameters params;
    Products products;
    Transform transform;
}

private:

@safe:

import cpptooling.data.representation : CppRoot, CppClass, CppMethod, CppCtor,
    CppDtor, CFunction, CppNamespace, USRType;
import cpptooling.data.type : LocationTag, Location;
import cpptooling.data.symbol.container : Container;
import dsrcgen.cpp : E;

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

    auto i_free_func = makeFuncInterface(input.funcRange, CppClassName(main_if), td_ns.resideInNs);
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

void postProcess(Controller ctrl, Parameters params, Products prods,
        Transform transf, ref GeneratedData gen_data) {
    import cpptooling.generator.includes : convToIncludeGuard,
        generatePreInclude, generatePostInclude, makeHeader;

    //TODO copied code from cstub. consider separating from this module to
    // allow reuse.
    static auto outputHdr(CppModule hdr, AbsolutePath fname, DextoolVersion ver,
            CustomHeader custom_hdr) {
        auto o = CppHModule(convToIncludeGuard(cast(FileName) fname));
        o.header.append(makeHeader(cast(FileName) fname, ver, custom_hdr));
        o.content.append(hdr);

        return o;
    }

    static auto output(CppModule code, AbsolutePath incl_fname, AbsolutePath dest,
            DextoolVersion ver, CustomHeader custom_hdr) {
        import std.path : baseName;

        auto o = new CppModule;
        o.suppressIndent(1);
        o.append(makeHeader(cast(FileName) dest, ver, custom_hdr));
        o.include(incl_fname.baseName);
        o.sep(2);
        o.append(code);

        return o;
    }

    auto test_double_hdr = transf.createHeaderFile(null);

    foreach (k, v; gen_data.uniqueData) {
        final switch (k) with (Code) {
        case Kind.hdr:
            prods.putFile(test_double_hdr, outputHdr(v,
                    test_double_hdr, params.getToolVersion, params.getCustomHeader));
            break;
        case Kind.impl:
            auto test_double_cpp = transf.createImplFile(null);
            prods.putFile(test_double_cpp, output(v, test_double_hdr,
                    test_double_cpp, params.getToolVersion, params.getCustomHeader));
            break;
        }
    }

    auto mock_incls = new CppModule;
    foreach (mock; gen_data.gmocks) {
        import std.algorithm : joiner, map;
        import std.conv : text;
        import std.format : format;
        import std.path : baseName;
        import std.string : toLower;
        import cpptooling.generator.gmock : generateGmockHdr;

        string repr_ns = mock.nesting.map!(a => a.toLower).joiner("-").text;
        string ns_suffix = mock.nesting.length != 0 ? "-" : "";
        auto fname = transf.createHeaderFile(format("_%s%s%s_gmock", repr_ns,
                ns_suffix, mock.name.toLower));

        mock_incls.include(fname.baseName);

        prods.putFile(fname, generateGmockHdr(cast(FileName) test_double_hdr,
                cast(FileName) fname, params.getToolVersion, params.getCustomHeader, mock));
    }

    if (gen_data.gmocks.length != 0) {
        auto fname = transf.createHeaderFile("_gmock");
        prods.putFile(fname, outputHdr(mock_incls, fname,
                params.getToolVersion, params.getCustomHeader));
    }

    if (ctrl.doPreIncludes) {
        prods.putFile(gen_data.includeHooks.preInclude,
                generatePreInclude(gen_data.includeHooks.preInclude), WriteStrategy.skip);
    }

    if (ctrl.doPostIncludes) {
        prods.putFile(gen_data.includeHooks.postInclude,
                generatePostInclude(gen_data.includeHooks.postInclude), WriteStrategy.skip);
    }
}
