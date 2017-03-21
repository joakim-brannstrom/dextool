module dextool.plugin.backend.fuzz.fuzzvariant;

import std.stdio;

///--------------------------
import std.typecons : No, Flag, Nullable, Yes;
import logger = std.experimental.logger;

import dsrcgen.cpp : CppModule, CppHModule;

//import application.types;
import dextool.type : FileName, DirName, MainName, StubPrefix, DextoolVersion,
    CustomHeader, MainNs, MainInterface;
import cpptooling.analyzer.clang.ast : Visitor;
//import cpptooling.testdouble.header_filter : LocationType;
import sutenvironment.sutenvironment;


/*@safe interface Controller {
    //Not needed atm
}
*/

/** Parameters used during generation.
 *
 * Important aspact that they do NOT change, therefore it is pure.
 */
@safe pure interface Parameters {
    static struct Files {
        FileName hdr;
        FileName impl;
        FileName globals;
        FileName gmock;
        FileName pre_incl;
        FileName post_incl;
    }

    Files getFiles();
    MainNs getMainNs();
    MainInterface getMainInterface();
    StubPrefix getArtifactPrefix();
    DextoolVersion getToolVersion();
    CustomHeader getCustomHeader();

    SUTEnvironment getSut();
}

/// Data produced by the generator like files.
@safe interface Products {
    void putFile(FileName fname, CppHModule hdr_data);
    void putFile(FileName fname, CppModule impl_data);
    void putLocation(FileName loc, LocationType type);
}

/// Generator of test doubles for C++ code.
struct Generator {
    import cpptooling.data.representation : CppRoot;
    import cpptooling.data.symbol.container : Container;

    private static struct Modules {
        import dextool.plugin.utility : MakerInitializingClassMembers;

        mixin MakerInitializingClassMembers!Modules;

        CppModule hdr;
        CppModule impl;
        CppModule gmock;
    }

     void process(ref CppRoot root, ref Container container) {
        import cpptooling.data.symbol.types : USRType;

        //auto fl = rawFilter(root, products, (USRType usr) => container.find!LocationTag(usr));
        //logger.trace("Filtered:\n", fl.toString());

        //auto impl_data = translate(fl, container, params);
        //logger.trace("Translated to implementation:\n", impl_data.toString());
        logger.trace("kind:\n", impl_data.kind);

        auto modules = Modules.make();
        generate(impl_data, params, modules, container);
        postProcess(params, products, modules);
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

	prods.putFile(params.getFiles.hdr, outputHdr(modules.hdr, params.getFiles.hdr, params.getToolVersion, params.getCustomHeader));
        prods.putFile(params.getFiles.impl, output(modules.impl, params.getFiles.hdr, params.getFiles.impl, params.getToolVersion, params.getCustomHeader));
    }
}

final class CppVisitor(RootT, ProductT) : Visitor {
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
        this(ProductT prod, uint indent, CppNsStack ns_stack,
                NullableRef!Container container) {
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

        auto ns_visitor = scoped!(CppVisitor!(CppNamespace, ProductT))(prod, indent, ns_stack, container);

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

enum Kind {
    none
}

struct ImplData {
    import cpptooling.data.type : CppMethodName;

    CppRoot root;
    alias root this;

    /// Tagging of nodes in the root
    Kind[size_t] kind;

    static auto make() {
        return ImplData(CppRoot.make);
    }

    void tag(size_t id, Kind kind_) {
        kind[id] = kind_;
    }

    Kind lookup(size_t id) {
        if (auto k = id in kind) {
            return *k;
        }

        return Kind.none;
    }
}

/*
  Will be implemented later
CppT rawFilter() {}
*/



/*
  Will be implemented later
auto translate() {}
*/



void generate(CppRoot r, Parameters params,
        Generator.Modules modules, ref const(Container) container)
in {
    import std.array : empty;

    assert(r.funcRange.empty);
}
body {
    import std.algorithm : each, filter;
    import std.array;
    import std.typecons;
    import cpptooling.data.symbol.types : USRType;
    import cpptooling.generator.func : generateFuncImpl;
    import cpptooling.generator.gmock : generateGmock;
    import cpptooling.generator.includes : generateIncludes;
    import cpptooling.data.representation;
    import cpptooling.analyzer.type;

    //generateIncludes(ctrl, params, modules.hdr);
    foreach (incl; params.getIncludes) {
        modules.hdr.include(cast(string) incl);
    }
    
    modules.hdr.include("testingenvironment.hpp");
    modules.hdr.include("portenvironment.hpp");
    
    static void gmockGlobal(T)(T r, CppModule gmock, Parameters params) {
        foreach (a; r.filter!(a => cast(ClassType) a.kind == ClassType.Gmock)) {
            generateGmock(a, gmock, params);
        }
    }

    // recursive to handle nested namespaces.
    // the singleton ns must be the first code generate or the impl can't
    // use the instance.
    @trusted static void eachNs(LookupT)(CppNamespace ns, Parameters params,
            Generator.Modules modules, CppModule impl_singleton, LookupT lookup, ref CppModule[string] classes) {
        import std.variant;
        import std.algorithm : canFind, map, joiner;
	    
        string currnsrp;	
        string currns = ns.fullyQualifiedName;

        
	    bool isReqOrPro = ns.resideInNs[$-1] == "Requirer" ||  ns.resideInNs[$-1] == "Provider";
        if (isReqOrPro) {
            currnsrp = join(ns.resideInNs[0..$-1], "::");
        } else {
            currnsrp = currns;
        }
        
        SUTEnv sut = params.getSut.GetSUTFromNamespace(currnsrp);
        auto inner = modules;
        CppModule inner_impl_singleton;
	    
        if(sut.valid) {
		    final switch(cast(NamespaceType) ns.kind) with (NamespaceType) {
	             case Normal:
                         inner.hdr = modules.hdr.namespace(ns.name);
                         //inner.hdr.suppressIndent(1);
                         inner.impl = modules.impl.namespace(ns.name);
                         break;
                     case TestDoubleSingleton:
                         break;
                     case TestDouble:
                         break;
            }
	    }
        
        if (sut.valid && isReqOrPro)
        {
            foreach(a; ns.classRange) {
                string class_name = a.name[2..$];
                string fqn_class = ns.fullyQualifiedName ~ "::"  ~ class_name;
                foreach (b; a.methodPublicRange) {
                    if (!(fqn_class in classes)) {
                        classes[fqn_class] = 
                            generateClass(inner, class_name, cast(string[])ns.resideInNs[0..$-1], ns.resideInNs[$-1].payload, sut);
                    } 
                    
                    b.visit!((const CppMethod a) => generateCppMeth(a, classes[fqn_class], class_name, ns.fullyQualifiedName, sut),
                        (const CppMethodOp a) => writeln(""),
                        (const CppCtor a) => generateCtor(a, inner),
                        (const CppDtor a) => generateDtor(a, inner));
                }
            }
        }
  
        foreach (a; ns.namespaceRange) { 
            eachNs(a, params, inner, inner_impl_singleton, lookup, classes);
        }
    }

    CppModule[string] classes;
    foreach (a; r.namespaceRange()) {
        eachNs(a, params, modules, null, (USRType usr) => container.find!LocationTag(usr), classes);
    }
}

@trusted string[] getDataItems(SUTEnv sut) {
    import std.algorithm : map, joiner, each; 
    import std.array;

    return sut.iface.interfaces.array.map!(a => map!(b => b.name)(a.ditems.array)).joiner.array;
}

@trusted CppModule generateClass(Generator.Modules inner, string class_name, string[] ns, string type, SUTEnv sut) {
    //Some assumptions are made. Does all interfaces start with I_? Does all providers and requirers end with Requirer or Provider?
    import std.array;
    import std.string : toLower, indexOf; 
    import std.algorithm : endsWith;
    
    string base_class; 
    string fqn_ns = ns.join("::"); 
    
    auto inner_class = inner.hdr.class_(class_name ~ "_Impl", "public I_" ~ class_name); 
    if (class_name.endsWith("Requirer") || class_name.endsWith("Provider")) {
        base_class = "I_" ~ class_name[0..class_name.indexOf(type)-1];
    } else {
        base_class = "";
    }

    with (inner_class) {
        with(private_) {
            foreach(ciface; sut.iface.interfaces) {
                stmt(E(fqn_ns ~ "::" ~ ciface.name ~ "T " ~ ciface.name.toLower));
            }
            if(class_name.endsWith("Requirer") || class_name.endsWith("Provider")) {
                stmt(E(base_class ~ "* port"));
            } else {
                stmt(E("RandomGenerator* randomGenerator"));
            }
        }
        with(public_) {
            with (func_body("", class_name ~ "_Impl")) { //Generate constructor
                if (!(class_name.endsWith("Requirer") || class_name.endsWith("Provider"))) {
                    stmt(E("randomGenerator") = E(`&TestingEnvironment::createRandomGenerator("`~ type  ~`")`));
                }
            }

            if ((class_name.endsWith("Requirer") || class_name.endsWith("Provider"))) {
                with (func_body("", class_name ~ "_Impl", base_class ~ "* p")) {
                    stmt(E("port") = E("p"));
                }
            }
	    
            with (func_body("", "~" ~ class_name ~"_Impl")) { //Generate destructor
             	    
            }
            if (!(class_name.endsWith("Requirer") || class_name.endsWith("Provider"))) {

                with(func_body("void", "Regenerate")) {
                    foreach(ciface; sut.iface.interfaces) {
                        foreach(ditem; ciface.ditems) {
                            //Add ranges here, non existent in current xml parser?
                         
                            stmt(E(ciface.name.toLower ~ "." ~ ditem.name) =    
                                    E(`randomGenerator->generate("` ~
                                        type ~ ` ` ~ ciface.name ~ ` ` ~ ditem.name ~ `")`));
                        }
                    }
                }
            }
        }
    }
    return inner_class;
}

void generateCtor(const CppCtor a, Generator.Modules inner) {
    import std.array : split;
    
    with (inner.impl.ctor_body(a.name)) {
    }                        
}   

void generateDtor(const CppDtor a, Generator.Modules inner) {
    import std.array : split;
    
    with (inner.impl.dtor_body(a.name[1..$])) {
    }                        
}


//Should probably return a class for implementation
@trusted void generateCppMeth(const CppMethod a, CppModule inner, string class_name, string nsname, SUTEnv sut) {
    //Get_Port, does it always exist?
    import std.string;
    import std.array;
    import std.algorithm.searching : canFind;
    import cpptooling.analyzer.type;

    auto ditems = getDataItems(sut);
    auto cppm_type = (cast(string)(a.name)).split("_")[0];
    auto cppm_ditem = (cast(string)(a.name)).split("_")[$-1];  
    

    if(cppm_type  == "Put") {
	//Put something in something
    }

    with(inner.func_body(a.returnType.toStringDecl, a.name)) {

        if(cppm_type == "Get" && ditems.array.canFind(cppm_ditem)) {
            auto cppm_ret_type = (cast(string)(a.name)).split("_")[$-2];
        
            return_(cppm_ret_type.toLower ~ "." ~ cppm_ditem);
        }

        else if (a.name == "Get_Port") {
            return_("*port");
        }

        else if(cppm_type == "Get") {
    		return_(cppm_ditem.toLower);
	    }
    }
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

    static CppClass.CppFunc[] getMethods(const ref CppClass c, ref Container container) @safe {
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
