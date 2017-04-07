module dextool.plugin.backend.fuzz.fuzzvariant;

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
import std.container.array;

struct nsclass {
    bool isPort;
    CppModule cppm;
    string name;
    string impl_name;
}

/** Parameters used during generation.
 *
 * Important aspact that they do NOT change, therefore it is pure.
 */
@safe pure interface Parameters {
    static struct Files {
        FileName hdr;
        FileName impl;
        FileName globals;
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
}

/// Data produced by the generator like files.
@safe interface Products {
    void putFile(FileName fname, CppHModule hdr_data);
    void putFile(FileName fname, CppModule impl_data);
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
        //logger.trace("Translated to implementation:\n", impl_data.toString());
        //logger.trace("kind:\n", impl_data.kind);

        //translate is skipped for now, as tagging isn't necessary

        auto modules = Modules.make();
        generate(new_root, params, modules, container, impl_data, xmlp);
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

        prods.putFile(params.getFiles.hdr, outputHdr(modules.hdr,
            params.getFiles.hdr, params.getToolVersion, params.getCustomHeader));
        prods.putFile(params.getFiles.impl, output(modules.impl,
            params.getFiles.hdr, params.getFiles.impl, params.getToolVersion,
            params.getCustomHeader));
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

enum Kind {
    none,
    ContinousInterface,
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

CppT rawFilter(CppT)(CppT input, xml_parse xmlp, ref CppNamespace[] out_) @trusted {
    import std.algorithm : each, map, filter;
    import dextool.type : FileName;
    import std.string : toLower;

    static if (is(CppT == CppRoot)) {
        auto filtered = CppRoot.make;
    } else static if (is(CppT == CppNamespace)) {
        auto filtered = input.dup;
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
    import cpptooling.generator.includes : generateIncludes;
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
        import std.array : join;

        auto inner = modules;
        CppModule inner_impl_singleton;

        final switch(data.lookup(ns.id)) with (Kind) {
          case none:
            writeln("namespace is none!");
            break;
          case ContinousInterface:
            writeln("Namespace is continous");
            break;
        }
        inner.hdr = modules.hdr.namespace(ns.resideInNs[0]);
        inner.impl = modules.impl.namespace(ns.resideInNs[0]);
        foreach (nss; ns.resideInNs[1 .. $]) {
            inner.hdr = inner.hdr.namespace(nss);
            inner.impl = inner.impl.namespace(nss);
        }

        string fqn_class = ns.fullyQualifiedName; // ~ "::"  ~ class_name;
        
        if (!(fqn_class in classes))
            classes[fqn_class] = Array!nsclass();

        foreach (a; ns.classRange) {

            string class_name = a.name; //Removes I_ 
            logger.trace("class_name: " ~ class_name);
            logger.trace("fqn_class: " ~ fqn_class);
            
            Namespace nss =  xmlp.getNamespace(ns.fullyQualifiedName.toLower);
            classes[fqn_class].insertBack(generateClass(inner, class_name,
                        ns.resideInNs[0 .. $ - 1].join("::"),
							ns.resideInNs[$ - 1].payload, nss, data, a, xmlp));

            foreach (b; a.methodPublicRange) {
                b.visit!((const CppMethod a) => generateCppMeth(a,
                    classes[fqn_class][$-1].cppm, class_name, fqn_class, nss),
                    (const CppMethodOp a) => writeln(""),
                    (const CppCtor a) => generateCtor(a, inner.impl),
                    (const CppDtor a) => generateDtor(a, inner.impl));
            }
        }

        foreach(a; ns.funcRange) {
	        generateFunc(inner.impl, a.returnType.toStringDecl, a.name, 
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

import cpptooling.data.type;
@trusted void generateFunc(CppModule inner, string return_type, string func_name, 
             string paramType, string paramName, Array!nsclass classes) {
    string port_name = "";
    string port_implname = "";
    string compif_name = "";
    string compif_implname = "";
    foreach(nss ; classes) {
        if (nss.isPort) {
            port_name = nss.name;
            port_implname = nss.impl_name;
        } else {
            compif_name = nss.name;
            compif_implname = nss.impl_name;
        }
    }
    with(inner.func_body(return_type, func_name, paramType ~ " " ~ paramName)) {
        if (paramType[$-1] == '&') {
            paramType = paramType[0..$-1]; //Remove reference
        }
	    return_(E(Et("PortEnvironment::createPort")(compif_implname, port_name, port_implname, paramType))(paramName ~ ", " ~ paramName));
    }
}

@trusted nsclass generateClass(Generator.Modules inner, string class_name,
			       string ns_full, string type, Namespace ns, ImplData data, CppClass class_, xml_parse xmlp) {
    //Some assumptions are made. Does all providers and requirers end with Requirer or Provider?
    import std.array;
    import std.string : toLower, indexOf;
    import std.algorithm : endsWith;

    auto inner_class = inner.impl.class_(class_name ~ "_Impl", "public " ~ class_name);
    nsclass sclass = nsclass(false, inner_class, class_name, class_name ~ "_Impl");
    
    final switch(data.lookup(class_.id)) with (Kind) {
        case none:
            sclass.isPort = true;
            generatePortClass(inner_class, class_name, ns, ns_full, type, xmlp);
            break;
        case ContinousInterface:
            generateCompIfaceClass(inner_class, class_name, ns, ns_full, type);
            break;
        }
    return sclass;
}
@trusted CppModule generateCompIfaceClass(CppModule inner_class, string class_name, Namespace ns, 
        string fqn_ns, string type) {
    import std.array;
    import std.string : toLower, indexOf;
    import std.algorithm : endsWith;

    string port_name = class_name;
    if (class_name.endsWith("Requirer")) {
        port_name = class_name[0..$-("_Requirer".length)];
    } else if (class_name.endsWith("Provider")) {
        port_name = class_name[0..$-("_Provider".length)];
    }

    with (inner_class) {
        with (private_) {
            logger.trace("class_name: " ~ class_name);
            logger.trace("generateClass fqn_ns: " ~ fqn_ns);

            stmt(E(port_name ~ "* port"));
        }
        with (public_) {
            with (func_body("", class_name ~ "_Impl")) { //Generate constructor
            }
            
            with (func_body("", class_name ~ "_Impl", port_name ~ "* p")) {
                stmt(E("port") = E("p"));
            }
        }
    }
    return inner_class;
}


@trusted CppModule generatePortClass(CppModule inner_class, string class_name,
				     Namespace ns, string fqn_ns, string type, xml_parse xmlp) {
    import std.array : empty;
    import std.string : toLower, indexOf, capitalize;
    import std.algorithm : endsWith;

    with (inner_class) {
        with (private_) {
            logger.trace("class_name: " ~ class_name);
            logger.trace("generateClass fqn_ns: " ~ fqn_ns);
            foreach (ciface; ns.interfaces.ci) {
                stmt(E(fqn_ns ~ "::" ~ ciface.name ~ "T " ~ ciface.name.toLower));
            }
            stmt(E("RandomGenerator* randomGenerator"));
        }
        with (public_) {
            with (func_body("", class_name ~ "_Impl")) { //Generate constructor
                stmt(
                    E("randomGenerator") = E(
                    `&TestingEnvironment::createRandomGenerator("` ~ type ~ `")`));
            }
            
            with (func_body("", "~" ~ class_name ~ "_Impl")) { /* Generate destructor */ }

            with (func_body("void", "Regenerate")) {
                foreach (ciface; ns.interfaces.ci) {
                    foreach (ditem; ciface.data_items) {
			string[string] minmax = xmlp.findMinMax(ns.name, ditem.type);
		      
			if (minmax.length > 0) {
			    string min = minmax["min"];
			    string max = minmax["max"];
			    string type_type = minmax["type"];
                string type_ns = minmax["namespace"];
			    
			    final switch (type_type) {
			    case "SubType":
				stmt(E(ciface.name.toLower ~ "." ~ ditem.name) = E(
									   `randomGenerator->generate("` ~ type ~ ` ` ~ ciface.name
									   ~ ` ` ~ ditem.name ~ `", `~min~`, `~max~`)`));
				break;
			    case "Enum":
				string fqns_type = type_ns.capitalize ~ "::" ~ ditem.type ~ "T::Enum";
				stmt(E(ciface.name.toLower ~ "." ~ ditem.name) = E(Et("static_cast")(fqns_type))(`randomGenerator->generate("`~type~` ` ~ ciface.name ~ ` ` ~ ditem.name~`", ` ~ min ~ `, ` ~ max ~ `)`));
				break;
			    case "Record":
				Variable[string] vars = xmlp.findVariables(type_ns, ditem.type);
				foreach (var_name ; vars) {
				    auto var_minmax = xmlp.findMinMax(ns.name, var_name.type);
				    if (var_minmax.length > 0) {
				    	stmt(E(ciface.name.toLower ~ "." ~ ditem.name ~ "." ~ var_name.name) = E(
									   `randomGenerator->generate("` ~ type ~ ` ` ~ ciface.name
									   ~ ` ` ~ ditem.name ~`", `~var_minmax["min"]~`, `~var_minmax["max"]~`)`));
				    }
				    else {
					stmt(E(ciface.name.toLower ~ "." ~ ditem.name ~ "." ~ var_name.name) = E(
										   `randomGenerator->generate("` ~ type ~ ` ` ~ ciface.name
										   ~ ` ` ~ ditem.name ~ `"`~`)`));
				    }
				}  
				
				break;
			    }
			}
			else {
			    stmt(E(ciface.name ~ "." ~ ditem.name) = E(
                            `randomGenerator->generate("` ~ type ~ ` ` ~ ciface.name
                            ~ ` ` ~ ditem.name ~ `"`~`)`));
			}
                    }
                }
    }
        }
    }
    return inner_class;
}

void generateCtor(const CppCtor a, CppModule inner) {
    import std.array : split;

    with (inner.ctor_body(a.name)) {
    }
}

void generateDtor(const CppDtor a, CppModule inner) {
    import std.array : split;

    with (inner.dtor_body(a.name[1 .. $])) {
    }
}

//Should probably return a class for implementation
@trusted void generateCppMeth(const CppMethod a, CppModule inner,
    string class_name, string nsname, Namespace ns) {
    //Get_Port, does it always exist?
    import std.string;
    import std.array;
    import std.algorithm : map;
    import std.algorithm.searching : canFind;
    import cpptooling.analyzer.type;
    import cpptooling.data.representation;

    auto cppm_type = (cast(string)(a.name)).split("_")[0];
    auto cppm_ditem = (cast(string)(a.name)).split("_")[$ - 1];

    if (cppm_type == "Get") {
        Flag!"isConst" meth_const = a.isConst ? Yes.isConst : No.isConst;
        with (inner.method_inline(No.isVirtual, a.returnType.toStringDecl, a.name, meth_const)) {
            string func_name = a.name["Get_".length .. $];
            ContinousInterface ci = getInterface(ns, func_name);
            if(ci.name != "") {
                func_name = func_name[ci.name.length .. $];
                if(func_name != "" && func_name[0] == '_') 
                    func_name = func_name[1..$];

                DataItem di = getDataItem(ns, ci, func_name);
                if (di.name == "") {
                    return_(ci.name.toLower);
                } else {
                    return_(ci.name.toLower ~ "." ~ di.name);
                }
            }
        }
    } else if (cppm_type == "Put") {
        auto params = joinParams(a.paramRange); 
        with (inner.method_inline(No.isVirtual, a.returnType.toStringDecl, a.name, No.isConst, params)) {
            string func_name = a.name["Get_".length .. $];
            ContinousInterface ci = getInterface(ns, func_name);
            if(ci.name != "") {
                func_name = func_name[ci.name.length .. $];
                if(func_name != "" && func_name[0] == '_') 
                    func_name = func_name[1..$];

                DataItem di = getDataItem(ns, ci, func_name);
                if (di.name == "") {
                    foreach(param ; a.paramRange) {
                        string paramName = paramNameToString(param);
                        stmt(E(ci.name.toLower ~ "." ~paramName) = E(paramName));
                    }
                } else {
                    stmt(E(ci.name.toLower ~ "." ~ di.name) = E(di.name));
                }
            }
        }
    } else {
        Flag!"isConst" meth_const = a.isConst ? Yes.isConst : No.isConst;
        with (inner.method_inline(No.isVirtual, a.returnType.toStringDecl, a.name, meth_const)) {
            stmt("return");
        }
    }
}

@trusted ContinousInterface getInterface(Namespace ns, string func_name) {
    ///func_name should have removed get_ or put_
    import std.string : indexOf;
    foreach(ci ; ns.interfaces.ci) {
        if(indexOf(func_name, ci.name) == 0) {
            return ci;
        } 
    }

    return ContinousInterface();   
}


@trusted DataItem getDataItem(Namespace ns, ContinousInterface ci, string func_name) {
    ///func_name should have removed Get_ or Put_ AND ci.name
    import std.string : indexOf;

    foreach(di; ci.data_items) {
        if (indexOf(func_name, di.name) == 0) {
            return di;
        }
    }
    return DataItem();
}
