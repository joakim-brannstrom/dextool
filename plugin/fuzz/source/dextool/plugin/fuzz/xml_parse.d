module xml_parse;

import std.algorithm;
import std.array;
import std.container.array;
import std.file;
import std.path;
import std.string;
import std.xml;
import std.typecons;

import std.stdio;


enum Direction {
    from = "requirer",
    to = "provider"
}

struct BaseDir {
    string basedir;
    alias basedir this;
}

struct Global {
    Array!Primitive prims;
    Array!SubType subtypes;
    Array!Record record;
    Array!Enum enums;

}
struct Types {
    Array!Primitive prims;
    Array!SubType subtypes;
    Array!Record record;
    Array!Enum enums;
    Global glob;

}

struct Record {
    string name;
    Variable[string] variables;

    this(string name) { this.name = name; }
}

struct Variable {
    string name;
    string type;
}

struct Enum {
    string name;
    Array!EnumItem enumitems;
    string min;
    string max;
    this(string name) { this.name = name; }
}

struct EnumItem {
    string name;
    string value;
}

struct SubType {
    this(string name, string type) {
        this.name = name;
        this.type = type;
    }

    string name;
    string type;
    string unit; ///Optional
    string min; ///Optional
    string max; ///Optional
}

struct ContinousInterface {
    string name;
    Direction direction;
    auto data_items = Array!DataItem();
}

struct Interface_ {
    Array!ContinousInterface ci;
    //Add more interfaces here
    alias ci this;
    //Add more alias here
}
struct DataItem {
    string name;
    string type;

    string startupVal;
    string defaultVal;
    this(string name, string type) {
        this.name = name;
        this.type = type;
    }
}

struct Namespace {
    string name;

    Types ns_types;
    Interface_ interfaces;
}

struct Primitive {
    string name;
    string type;
    string size;

    CPPInterface cppint;

    this(string name, string type, string size) { this.name = name; this.type = type; this.size = size; }
}

struct CPPInterface {
    string header;
}


class xml_parse
{
private:
        string basedir;
        string[] foundNamespaces;
        string[] xml_files;
        Namespace[string] nsps;

        string namespace(string filename) {
        ///TODO: Namespaces should probably only be added if there is any interface in the file
        //dfmt off
            if (baseName(filename, ".xml") == "types") {
                return dirName(filename)
                    .chompPrefix(this.basedir)
                    .replace(dirSeparator, "::")
                    .chompPrefix("::");
            }

            return dirName(filename)
                .chompPrefix(this.basedir)
                .replace(dirSeparator, "::")
                .chompPrefix("::")
                ~ "::" ~ baseName(filename, ".xml");
        //dfmt on
        }

        Types getTypes(Element types) {
            import std.stdio;
            import std.conv;
            import std.typecons;

            Types xml_types;
            foreach (Element elem; types.elements) {
                final switch (elem.tag.name) {
                    case "SubType":
                        SubType subtype = SubType(elem.tag.attr["name"], elem.tag.attr["type"]);
                        if (auto minVal = "min" in elem.tag.attr) {
                            subtype.min = *minVal;
                        }

                        if (auto maxVal = "max" in elem.tag.attr) {
                            subtype.max = *maxVal;
                        }

                        if (auto unit = "unit" in elem.tag.attr) {
                            subtype.unit = *unit;
                        }
                        xml_types.subtypes.insertBack(subtype);
                        break;

                    case "Record":
                        Record rec = Record(elem.tag.attr["name"]);
                        foreach (Element variable ; elem.elements) {
                            Variable var = Variable(variable.tag.attr["name"], variable.tag.attr["type"]);
                            rec.variables[variable.tag.attr["name"]] = var;
                        }
                        xml_types.record.insertBack(rec);
                        break;
                    case "Enum":
                        Enum enums = Enum(elem.tag.attr["name"]);
                        Nullable!int min;
                        Nullable!int max;                       
                        foreach(Element enumitem ; elem.elements) {
                            auto val = to!int(enumitem.tag.attr["value"]);
                            if (min.isNull && max.isNull) {
                                min = val;
                                max = val;
                            } else if (max < val) {
                                max = val;
                            } else if (min > val) {
                                min = val;
                            }
                            enums.enumitems.insertBack(EnumItem(enumitem.tag.attr["name"],
                                enumitem.tag.attr["value"]));
                        }
                        enums.min = to!string(min);
                        enums.max = to!string(max);
                        xml_types.enums.insertBack(enums);
                        break;
                    case "Primitive":
                        Primitive prim = Primitive(elem.tag.attr["name"], elem.tag.attr["type"], elem.tag.attr["size"]);
                        prim.cppint = CPPInterface(elem.elements[0].tag.attr["header"]);
                        xml_types.prims.insertBack(prim);
                        break;
                }
            }
            return xml_types;
        }

        auto getContinousInterface(Element interface_elem) {
            Interface_ ret;
            ContinousInterface cis;
            //Add more interfaces here
            cis.name = interface_elem.tag.attr["name"];
            cis.direction = interface_elem.tag.attr["direction"] == "From_Provider" ? Direction.from : Direction.to;
            foreach (Element elem; interface_elem.elements) {
                switch (elem.tag.name) {
                    case "DataItem":
                        DataItem data_item = DataItem(elem.tag.attr["name"],
                            elem.tag.attr["type"]);
                        if (auto defaultVal = "defaultValue" in elem.tag.attr) {
                            data_item.defaultVal = *defaultVal;
                        }

                        if (auto startupVal = "startupValue" in elem.tag.attr) {
                            data_item.startupVal = *startupVal;
                        }
                        cis.data_items.insertBack(data_item);

                        break;
                    default:
                        break;
                }
            }

            return cis;
        }

        Types[] types(Document doc) {
            if (doc.tag.name == "Types") { //Everything is a type!
                return [getTypes(doc)];
            } else {
                return doc.elements.filter!(a => a.tag.name == "Types").map!(a => getTypes(a)).array;
            }
        }

        Nullable!Interface_ interfaces(Document doc) {
            Nullable!Interface_ ret;
            if (doc.tag.name != "Interface") {
                return ret;
            } else {
                ret = Interface_();
                foreach(Element elem ; doc.elements) {
                    switch (elem.tag.name) {
                        case "ContinousInterface":
                            ret.ci.insertBack(getContinousInterface(elem));
                            break;
                        default:
                            break;
                    }
                }
            }
            return ret;
        }

        Types merge(Types[] old) {
            Types new_;
            foreach(Types old_types ; old) {
                new_.enums = old_types.enums ~ new_.enums;
                new_.prims = old_types.prims ~ new_.prims;
                new_.record = old_types.record ~ new_.record;
                new_.subtypes = old_types.subtypes ~ new_.subtypes;
            }
            return new_;
        }

        Types merge(Types old, ref Types new_) {
            new_.enums = old.enums ~ new_.enums;
            new_.prims = old.prims ~ new_.prims;
            new_.record = old.record ~ new_.record;
            new_.subtypes = old.subtypes ~ new_.subtypes;

            return new_;
        }

        Interface_ merge(Interface_ old, Interface_ new_) {
            new_.ci = old.ci ~ new_.ci;

            return new_;
        } 

public:
    this(BaseDir bdir)
    {
        basedir = bdir;
        xml_files = (dirEntries(this.basedir, "*.xml", SpanMode.breadth).filter!(a => a.isFile)).map!(a => a.name)
            .array;
        foundNamespaces = xml_files.map!(a => namespace(a)).filter!(a => a!= "").array;
        nsps = parseBaseDir;
    }

    Namespace[string] parseBaseDir() {
        import std.stdio;
        Namespace[string] namespaces;
        Global glob;
        foreach(string xml_file ; xml_files) {
            string curr_ns = namespace(xml_file);
            auto doc = new Document(cast(string) std.file.read(xml_file));
            Types ntypes = merge(types(doc));
            Nullable!Interface_ ifaces = interfaces(doc);

            if (curr_ns == "global") {
                namespaces["global"] = Namespace("global", ntypes, Interface_());
                glob.enums = ntypes.enums ~ glob.enums;
                glob.prims = ntypes.prims ~ glob.prims;
                glob.record = ntypes.record ~ glob.record;
                glob.subtypes = ntypes.subtypes ~ glob.subtypes;

                continue;
            }
            if(ifaces.isNull) {
                namespaces[curr_ns] = Namespace(curr_ns, ntypes, Interface_()); //Add nullable to interface_ as standard?
                continue;
            }
            foreach (ContinousInterface c ; ifaces.ci) {
                string tmp_ns = curr_ns ~ "::" ~ c.direction;
                if (auto ns = tmp_ns in namespaces) {
                    namespaces[tmp_ns].ns_types = merge(ntypes, ns.ns_types);
                    namespaces[tmp_ns].interfaces = merge(ifaces, ns.interfaces);
                } else {
                    namespaces[tmp_ns] = Namespace(tmp_ns, ntypes, ifaces);
                }
            }
        }

        foreach (string key ; namespaces.byKey) {
            namespaces[key].ns_types.glob = glob;
        }

        return namespaces;
    }

    Namespace[string] getNamespaces() {
        return this.nsps;
    }

    bool exists(string nsname) {
	return this.nsps.get(nsname, Namespace()) != Namespace();
    }

    Namespace getNamespace(string nsname) {
        return this.nsps[nsname];
    }

    Types traverseNamespace(string topns, ref Types out_types) {
        auto ns_spl = topns.split("::");
        if(auto ns = ns_spl.join("::") in getNamespaces) {
            out_types = merge(ns.ns_types, out_types);
            return traverseNamespace(ns_spl[0..$-1].join("::"), out_types);
        }
        else if (ns_spl.length >= 1) {
            return traverseNamespace(ns_spl[0..$-1].join("::"), out_types);
        }

        if(auto ns = "global" in getNamespaces) {
            return merge(ns.ns_types, out_types);
        }
        return out_types;
    }

    string[string] findMinMax(string topns, string type_name) {
	string[string] ret;
	Types out_types;
	out_types = traverseNamespace(topns, out_types);

	/*Array!Primitive prims;
	  Array!SubType subtypes;
	  Array!Record record;
	  Array!Enum enums;*/
	foreach (SubType t ; out_types.subtypes) {
	    if (t.name == type_name) {
		ret["min"] = t.min;
		ret["max"] = t.max;
		ret["type"] = "SubType";
		return ret;
	    }
	}
	foreach (Enum t ; out_types.enums) {
	    if (t.name == type_name) {
		ret["min"] = t.min;
		ret["max"] = t.max;
		ret["type"] = "Enum";
		return ret;
	    }
	}

	return ret;
    }

    
    

}



version(none) {
    int main() {
        Types out_t = Types();
        xml_parse xml_p = new xml_parse(BaseDir("sut_unittest/namespaces"));

        xml_p.traverseNamespace("foo::bar::requirer", out_t);
        foreach (a ; out_t.prims) {
            writeln(a);
        }

        return 0;
    }
    
}

