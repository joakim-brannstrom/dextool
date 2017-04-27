module backend.fuzz.fuzzvariant;

import std.stdio;

///--------------------------
import std.typecons : No, Flag, Nullable, Yes;
import logger = std.experimental.logger;

import dsrcgen.cpp : CppModule, CppHModule;
import dsrcgen.cpp;

//import application.types;
import dextool.type : FileName, DirName, MainName, StubPrefix, DextoolVersion,
    CustomHeader, MainNs, MainInterface;
import cpptooling.analyzer.clang.ast : Visitor;

//import application.types;
import cpptooling.testdouble.header_filter : LocationType;

import xml_parse;
import backend.fuzz.generators;
import backend.fuzz.types;
import std.container.array;



/** Parameters used during generation.
 *
 * Important aspact that they do NOT change, therefore it is pure.
 */
@safe pure interface Parameters {
    static struct Files {
        FileName hdr;
        FileName impl;
        FileName main;
        FileName main_hdr;
        FileName pre_incl;
        FileName post_incl;
    }

    BaseDir getXMLBasedir();
    @trusted string[] getIncludes();
    Files getFiles();
    MainNs getMainNs();
    MainInterface getMainInterface();
    StubPrefix getArtifactPrefix();
    DextoolVersion getToolVersion();
    CustomHeader getCustomHeader();
    AppName getAppName();
}

/// Data produced by the generator like files.
@safe interface Products {
    void putFile(FileName fname, CppHModule hdr_data);
    void putFile(FileName fname, CppModule impl_data);
}

struct Generator {
    import cpptooling.data.representation : CppRoot;
    import cpptooling.data.symbol.container : Container;

    private static struct Modules {
        import dextool.plugin.utility : MakerInitializingClassMembers;

        mixin MakerInitializingClassMembers!Modules;

        CppModule hdr;
        CppModule impl;
        CppModule main;
        CppModule main_hdr;
    }

    this(Parameters params, Products products) {
        this.params = params;
        this.products = products;
    }

    void process(ref CppRoot root, ref Container container) {
        import cpptooling.data.symbol.types : USRType;
        import std.algorithm;
        import std.string : toLower;

        //TODO: Find a suitable name
        xml_parse xmlp = new xml_parse(params.getXMLBasedir);
        CppRoot new_root = CppRoot.make;
        CppNamespace[] cppn;

        rawFilter(root, xmlp, cppn);

        cppn.each!(a => new_root.put(a));
        auto impl_data = translate(new_root);

        auto modules = Modules.make();
        makeMain(modules);
        generate(new_root, params, modules, container, impl_data, xmlp);
        postProcess(params, products, modules);
    }

    void makeMain(Modules modules) {
        generateMainFunc(modules.main, params.getAppName);
        generateMainHdr(modules.main_hdr);
    }

private:
    Parameters params;
    Products products;

    static void postProcess(Parameters params, Products prods, Modules modules) {
        import cpptooling.generator.includes : convToIncludeGuard,
            generatetPreInclude, generatePostInclude, makeHeader;

        static auto outputHdr(CppModule hdr, FileName fname, DextoolVersion ver,
            CustomHeader custom_hdr) {
            auto o = CppHModule(convToIncludeGuard(fname));
            o.header.append(makeHeader(fname, ver, custom_hdr));
            o.content.append(hdr);

            return o;
        }

        static auto outputMainHdr(CppModule hdr, FileName fname, DextoolVersion ver) {
            auto o = CppHModule(convToIncludeGuard(fname));
            o.header.append(makeHeader(fname, ver, CustomHeader()));
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

        static auto outputMain(CppModule code, FileName main_incl, FileName dest, DextoolVersion ver) {
            import std.path : baseName;

            auto o = new CppModule;
            o.suppressIndent(1);
            o.append(makeHeader(dest, ver, CustomHeader()));
            o.include(main_incl.baseName);
            o.sep(2);
            o.append(code);

            return o;
        }


        prods.putFile(params.getFiles.hdr, outputHdr(modules.hdr,
            params.getFiles.hdr, params.getToolVersion, params.getCustomHeader));

        prods.putFile(params.getFiles.main_hdr, outputMainHdr(modules.main_hdr,
            params.getFiles.main_hdr, params.getToolVersion));
        
        prods.putFile(params.getFiles.impl, output(modules.impl,
            params.getFiles.hdr, params.getFiles.impl, params.getToolVersion,
            params.getCustomHeader));

        prods.putFile(params.getFiles.main, outputMain(modules.main,
            params.getFiles.main_hdr, params.getFiles.main, params.getToolVersion));
    }
}

final class FuzzVisitor(RootT, ProductT) : Visitor {
    import std.typecons : scoped, NullableRef;

    import cpptooling.analyzer.clang.ast : UnexposedDecl, VarDecl, FunctionDecl,
        ClassDecl, Namespace, TranslationUnit, generateIndentIncrDecr;
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
        ProductT prod;
        CppNsStack ns_stack;
    }

    static if (is(RootT == CppRoot)) {
        // The container used is stored in the root.
        // All other visitors references the roots container.
        Container container_;

        this(ProductT prod) {
            this.prod = prod;
            this.root = CppRoot.make;
            this.container = &container_;
        }
    } else {
        this(ProductT prod, uint indent, CppNsStack ns_stack, NullableRef!Container container) {
            this.root = CppNamespace(ns_stack);
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
            auto func = CFunction(result.type.kind.usr, result.name,
                result.params, CxReturnType(result.returnType),
                result.isVariadic, result.storageClass);
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
        logger.trace("class: ", v.cursor.spelling);

        if (v.cursor.isDefinition) {
            auto visitor = scoped!ClassVisitor(v, ns_stack, container, indent + 1);
            v.accept(visitor);

            root.put(visitor.root);
            //container.put(visitor.root, visitor.root.fullyQualifiedName);
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

        auto ns_visitor = scoped!(FuzzVisitor!(CppNamespace, ProductT))(prod,
            indent, ns_stack, container);

        v.accept(ns_visitor);

        // fill the namespace with content from the analysis
        root.put(ns_visitor.root);
    }

    override void visit(const(TranslationUnit) v) {
        import std.algorithm : filter;
        import cpptooling.analyzer.clang.type : makeLocation;

        mixin(mixinNodeLog!());

        LocationTag tu_loc;
        () @trusted{ tu_loc = LocationTag(Location(v.cursor.spelling, 0, 0)); }();

        v.accept(this);
    }

    void toString(Writer)(scope Writer w) @safe const {
        import std.format : FormatSpec;
        import std.range.primitives : put;

        auto fmt = FormatSpec!char("%u");
        fmt.writeUpToNextSpec(w);

        root.toString(w, fmt);
        put(w, "\n");
        container.get.toString(w, FormatSpec!char("%s"));
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
    CppDtor, CFunction, CppNamespace, USRType;
import cpptooling.data.type : LocationTag, Location;
import cpptooling.data.symbol.container : Container;
import dsrcgen.cpp : E;



CppT rawFilter(CppT)(CppT input, xml_parse xmlp, ref CppNamespace[] out_) @trusted {
    import std.algorithm : each, map, filter;
    import dextool.type : FileName;
    import std.string : toLower;
    import cpptooling.data.representation : MergeMode;

    static if (is(CppT == CppRoot)) {
        auto filtered = CppRoot.make;
    } else static if (is(CppT == CppNamespace)) {
        auto filtered = CppNamespace(input.resideInNs);
        filtered.merge(input, MergeMode.full);
    }

    // dfmt off
    input.namespaceRange
        .filter!(a => !a.isAnonymous)
        .map!(a => rawFilter(a, xmlp, out_))
        .filter!(a => a.fullyQualifiedName.toLower in xmlp.getNamespaces)
        .each!(a => out_ = out_ ~ a);
            
    // dfmt on
    return filtered;
}

ImplData translate(CppRoot root) {
    import std.algorithm : map, filter, each;

    auto r = ImplData.make;

    // dfmt off
    root.namespaceRange
        .map!(a => translate(a, r))
        .filter!(a => !a.isNull)
        .each!(a => r.put(a.get));

    root.classRange
        .map!(a => translate(a, r))
        .filter!(a=> !a.isNull)
        .each!(a => r.put(a.get));

    return r;
}

Nullable!CppClass translate(CppClass input, ref ImplData data) {
    import std.algorithm : endsWith;
    string name = input.name;
    auto ReqOrPro = name.endsWith("Requirer") || name.endsWith("Provider");
    Nullable!CppClass class_ = input;
    if (ReqOrPro) {
        data.tag(input.id, Kind.ContinousInterface);
    }

    return class_;
}

Nullable!CppNamespace translate(CppNamespace input, ref ImplData data) {
    import std.algorithm : map, filter, each;
    auto ReqOrPro = input.name  == "Requirer"
        || input.name == "Provider";
    Nullable!CppNamespace ns = input;
    if (ReqOrPro) {
        data.tag(ns.id, Kind.ContinousInterface);
    }

    input.classRange
        .map!(a => translate(a, data))
        .filter!(a => !a.isNull)
        .each!(a => data.put(a.get));
    return ns;
}



void generate(CppRoot r, Parameters params, Generator.Modules modules,
    ref const(Container) container, ImplData data, xml_parse xmlp)
in {
    import std.array : empty;

    //assert(r.funcRange.empty);
}
body {
    import std.algorithm : each, filter;
    import std.array;
    import std.typecons;
    import std.container.array;
    import cpptooling.data.symbol.types : USRType;
    import cpptooling.generator.func : generateFuncImpl;
    import cpptooling.data.representation;
    import cpptooling.analyzer.type;


    foreach (incl; params.getIncludes) {
        modules.hdr.include(incl);
    }

    modules.hdr.include("testingenvironment.hpp");
    modules.hdr.include("portenvironment.hpp");

    // recursive to handle nested namespaces.
    // the singleton ns must be the first code generate or the impl can't
    // use the instance.

    @trusted static void eachNs(LookupT)(CppNamespace ns, Parameters params,
        Generator.Modules modules, CppModule impl_singleton, LookupT lookup, ImplData data,
        ref Array!nsclass[string] classes, xml_parse xmlp) {
        import std.variant;
        import std.stdio;
        import std.string : toLower, indexOf;
        import std.algorithm : canFind, map, joiner;
        import backend.fuzz.generators;

        auto inner = modules;
        CppModule inner_impl_singleton;


        inner.hdr = modules.hdr.namespace(ns.resideInNs[0]);
        inner.impl = modules.impl.namespace(ns.resideInNs[0]);
        foreach (nss; ns.resideInNs[1 .. $]) {
            inner.hdr = inner.hdr.namespace(nss);
            inner.impl = inner.impl.namespace(nss);
        }

        string fqn_class = ns.fullyQualifiedName;
        
        if (!(fqn_class in classes))
            classes[fqn_class] = Array!nsclass();

        foreach (a; ns.classRange) {

            string class_name = a.name; //Removes I_ 
            logger.trace("class_name: " ~ class_name);
            logger.trace("fqn_class: " ~ fqn_class);
            
            Namespace nss =  xmlp.getNamespace(ns.fullyQualifiedName.toLower);
            classes[fqn_class].insertBack(generateClass(inner.impl, class_name,
                        ns.resideInNs,
							nss, data, a, xmlp));

            foreach (b; a.methodPublicRange) {
                b.visit!((const CppMethod a) => generateCppMeth(a,
                    classes[fqn_class][$-1].cppm, class_name, fqn_class, nss),
                    (const CppMethodOp a) => writeln(""),
                    (const CppCtor a) => generateCtor(a, inner.impl),
                    (const CppDtor a) => generateDtor(a, inner.impl));
            }
        }

        foreach(a; ns.funcRange) {
            if(a.name == "Create_Instance")
	            generateCreateInstance(inner.impl, a.returnType.toStringDecl, a.name, 
                    paramTypeToString(a.paramRange[0]), paramNameToString(a.paramRange[0]),classes[fqn_class]);
        }

        
        foreach (a; ns.namespaceRange) {
            eachNs(a, params, inner, inner_impl_singleton, lookup, data, classes, xmlp);
        }
    }

    Array!nsclass[string] classes;
    foreach (a; r.namespaceRange()) {
        eachNs(a, params, modules, null,
            (USRType usr) => container.find!LocationTag(usr), data, classes, xmlp);
    }
} 