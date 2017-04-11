module backend.fuzz.generators;

import std.container.array;
import std.typecons;
import logger = std.experimental.logger;


import cpptooling.data.type;
import cpptooling.data.representation;

import dsrcgen.cpp;

import xml_parse;
import backend.fuzz.types;

@trusted void generateCreateInstance(CppModule inner, string return_type, string func_name, 
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

    assert(port_name.length != 0);
    assert(port_implname.length != 0);
    assert(compif_name.length != 0);
    assert(compif_implname.length != 0);

    with(inner.func_body(return_type, func_name, paramType ~ " " ~ paramName)) {
        if (paramType[$-1] == '&') {
            paramType = paramType[0..$-1]; //Remove reference
        }
	return_(E(Et("PortEnvironment::createPort")(compif_implname, port_name, port_implname, paramType))(paramName ~ ", " ~ paramName));
    }
}

@trusted nsclass generateClass(CppModule inner, string class_name,
			       string ns_full, string type, Namespace ns, ImplData data, CppClass class_, xml_parse xmlp) {
    //Some assumptions are made. Does all providers and requirers end with Requirer or Provider?
    import std.array;
    import std.string : toLower, indexOf;
    import std.algorithm : endsWith;

    auto inner_class = inner.class_(class_name ~ "_Impl", "public " ~ class_name);
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
    import std.format : format;

    with (inner_class) {
        with (private_) {
            logger.trace("class_name: " ~ class_name);
            logger.trace("generateClass fqn_ns: " ~ fqn_ns);
            foreach (ciface; ns.interfaces.ci) {
                stmt(E(format("%s::%sT %s", fqn_ns, ciface.name, ciface.name.toLower)));
            }
            stmt(E("RandomGenerator* randomGenerator"));
        }
        
        with (public_) {
            with (func_body("", class_name ~ "_Impl")) { //Generate constructor
		        string expr = format(`%s::%s("%s")`, "&TestingEnvironment", "createRandomGenerator", type);
                stmt(E("randomGenerator") = E(expr));
            }
            
            with (func_body("", "~" ~ class_name ~ "_Impl")) { /* Generate destructor */ }

            auto func = func_body("void", "Regenerate"); 
	        foreach (ciface; ns.interfaces.ci) {
		        foreach (ditem; ciface.data_items) {
		            string[string] minmax = xmlp.findMinMax(ns.name, ditem.type, ditem);
		      
		            if (minmax.length > 0) {
                        string defVal = minmax["defVal"];
			            string min = minmax["min"];
                        string max = minmax["max"];
                        string type_type = minmax["type"];
                        string type_ns = minmax["namespace"];
			    
                        switch (type_type) {
                            case "SubType":
                                generateSubType(func, ciface.name, ditem.name, type, min, max, defVal);
                                break;
                            case "Enum":
                                generateEnum(func, ciface.name, ditem.name, type_ns, type, ditem.type, min, max);
                                break;
                            case "Record":			
                                generateRecord(func, ciface.name, ditem.name, ns.name, type_ns, type, ditem.type, xmlp);
                                break;
                            default:
                                break;
                            }
                        } else {
                            string var = format("%s.%s", ciface.name.toLower, ditem.name);
                            string expr = format(`randomGenerator->generate("%s %s %s")`,
                                        type, ciface.name, ditem.name);
                            stmt(E(var) = E(expr));
                        }
		        }   
	        }    
        }
    }
    return inner_class;
}

@trusted void generateSubType(CppModule func, string ciface_name, string ditem_name, string type,
		     string min, string max, string defVal) {
    import std.format : format;
    import std.string : toLower;

    string var = format("%s.%s", ciface_name.toLower, ditem_name);
    string expr;
    if (defVal.length == 0) {
        expr = format(`randomGenerator->generate("%s %s %s", %s, %s)`,
                type, ciface_name, ditem_name, min, max);
    } else {
        expr = defVal;
    }

    with (func) { stmt(E(var) = E(expr)); }
}

@trusted void generateEnum(CppModule func, string ciface_name, string ditem_name, string type_ns,
		  string type,  string ditem_type, string min, string max) { 
    import std.format : format;
    import std.string : toLower, capitalize;

    string var = format("%s.%s", ciface_name.toLower, ditem_name);
    string fqns_type = format("%s::%sT::Enum", type_ns.capitalize, ditem_type);
    string expr = format(`randomGenerator->generate("%s %s %s", %s, %s)`, 
			 type, ciface_name, ditem_name, min, max);

    with (func) { stmt(E(var) = E(Et("static_cast")(fqns_type))(expr)); }
}

@trusted void generateRecord(CppModule func, string ciface_name, string ditem_name, string ns_name,
		    string type_ns, string type, string ditem_type, xml_parse xmlp) { 
    import std.format : format;
    import std.string : toLower;

    Variable[string] vars = xmlp.findVariables(type_ns, ditem_type);
    foreach (var_name ; vars) {
        auto var_minmax = xmlp.findMinMax(ns_name, var_name.type, DataItem());
        if (var_minmax.length > 0) {
            string var = format("%s.%s.%s", ciface_name.toLower, ditem_name, var_name.name);
            string expr;
            if (var_minmax["defVal"].length == 0) {
                expr = format(`randomGenerator->generate("%s %s %s", %s, %s)`,
                    type, ciface_name, ditem_name, var_minmax["min"], var_minmax["max"]);
            } else {
                expr = var_minmax["defVal"];
            }

            with (func) { stmt(E(var) = E(expr)); }
        }
        else {
            string var = format("%s.%s.%s", ciface_name.toLower, ditem_name, var_name.name);
            string expr = format(`randomGenerator->generate("%s %s %s")`,
                    type, ciface_name, ditem_name);

            with (func) { stmt(E(var) = E(expr)); }
        }
    }  
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

//TODO: Split this function to multiple and add cppm_type as a tag in translate()
@trusted void generateCppMeth(const CppMethod a, CppModule inner,
    string class_name, string nsname, Namespace ns) {

    import std.string;
    import std.array;
    import std.algorithm : map;
    import std.algorithm.searching : canFind;
    import cpptooling.analyzer.type;
    import cpptooling.data.representation;

    auto cppm_type = (cast(string)(a.name)).split("_")[0];
    auto cppm_ditem = (cast(string)(a.name)).split("_")[$ - 1];

    switch(cppm_type) {
        case "Get":
            generateGetFunc(a, inner, ns);
            break;
        case "Put":
            generatePutFunc(a, inner, ns);
            break;
        default:
            Flag!"isConst" meth_const = a.isConst ? Yes.isConst : No.isConst;
            with (inner.method_inline(No.isVirtual, a.returnType.toStringDecl, a.name, meth_const)) {
                return_;
            }
            break;
    }
}

@trusted void generateGetFunc(const CppMethod a, CppModule inner, Namespace ns) {
    import std.string : toLower;
    import cpptooling.data.representation;
    import cpptooling.analyzer.type;

    if(a.name == "Get_Port") {
        with(inner.method_inline(No.isVirtual, a.returnType.toStringDecl, a.name, No.isConst)) {
            return_("*port");
        }
    } else {
        Flag!"isConst" meth_const = a.isConst ? Yes.isConst : No.isConst;
        with (inner.method_inline(No.isVirtual, a.returnType.toStringDecl, a.name, meth_const)) {
            string func_name = a.name["Get_".length .. $];
            ContinousInterface ci = getInterface(ns, func_name);
            if(ci.name.length != 0) {
                func_name = func_name[ci.name.length .. $];
                if(func_name.length != 0 && func_name[0] == '_') 
                    func_name = func_name[1..$];

                DataItem di = getDataItem(ns, ci, func_name);
                if (di.name.length == 0) {
                    return_(ci.name.toLower);
                } else {
                    return_(ci.name.toLower ~ "." ~ di.name);
                }
            }
        }
    }
}

@trusted void generatePutFunc(const CppMethod a, CppModule inner, Namespace ns) {
    import std.string : toLower;
    import cpptooling.data.representation;
    import cpptooling.analyzer.type;

    auto params = joinParams(a.paramRange); 
    with (inner.method_inline(No.isVirtual, a.returnType.toStringDecl, a.name, No.isConst, params)) {
        string func_name = a.name["Get_".length .. $];
        ContinousInterface ci = getInterface(ns, func_name);
        if(ci.name.length != 0) {
            func_name = func_name[ci.name.length .. $];
            if(func_name.length != 0 && func_name[0] == '_') 
                func_name = func_name[1..$];

            DataItem di = getDataItem(ns, ci, func_name);
            if (di.name.length == 0) {
                foreach(param ; a.paramRange) {
                    string paramName = paramNameToString(param);
                    stmt(E(ci.name.toLower ~ "." ~paramName) = E(paramName));
                }
            } else {
                stmt(E(ci.name.toLower ~ "." ~ di.name) = E(di.name));
            }
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
