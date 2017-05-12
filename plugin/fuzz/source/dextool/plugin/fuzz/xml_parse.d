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

import logger = std.experimental.logger;

@safe:

enum Direction {
    from = "requirer",
    to = "provider"
}

enum InterfaceType {
    E_iface = "eiface",
    C_iface = "ciface"
}

struct BaseDir {
    string basedir;
    alias basedir this;
}

struct Global {
    Primitive[] prims;
    SubType[] subtypes;
    Record[] record;
    Enum[] enums;
}

struct Types {
    Primitive[] prims;
    SubType[] subtypes;
    Record[] record;
    Enum[] enums;
    Global glob;

}

struct Record {
    string name;
    string namespace;
    Variable[string] variables;

    this(string name, string ns) {
        this.name = name;
        this.namespace = ns;
    }
}

struct Variable {
    string name;
    string type;

    string defaultVal;
    string min;
    string max;
}

struct Enum {
    string name;
    EnumItem[] enumitems;
    string min;
    string max;
    string namespace;
    this(string name, string ns) {
        this.name = name;
        this.namespace = ns;
    }
}

struct EnumItem {
    string name;
    string value;
}

struct SubType {
    this(string name, string type, string ns) {
        this.name = name;
        this.type = type;
        this.namespace = ns;
    }

    string name;
    string type;
    string namespace;
    string unit; ///Optional
    string min; ///Optional
    string max; ///Optional
}

struct ContinousInterface {
    string name;
    Direction direction;
    DataItem[] data_items;
    MonitoredItem[] mon_items;
}

struct Interface_ {
    ContinousInterface[] ci;
    EventGroupInterface[] ei;

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

struct MonitoredItem { //Same as DataItem and Event
    string name;
    string type;

    string startupVal;
    string defaultVal;
    this(string name, string type) {
        this.name = name;
        this.type = type;
    }
}

struct MonitoredChange {
    string name; //Should be empty.
}

struct EventGroupInterface {
    string name;
    string direction;
    Event[] events;
}

struct Event { //Same as DataItem and MonitoredItem
    string name;
    DataItem[] data_items;
    this(string name) {
        this.name = name;
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

    this(string name, string type, string size) {
        this.name = name;
        this.type = type;
        this.size = size;
    }
}

struct CPPInterface {
    string header;
}

class xml_parse {
private:
    BaseDir[] basedir;
    string[] foundNamespaces;
    string[] xml_files;
    Namespace[string] nsps;

    string namespace(string filename) {
        ///TODO: Namespaces should probably only be added if there is any interface in the file
        //dfmt off
        foreach(n; this.basedir) {
            if(filename.canFind(n.basedir)) {
                return dirName(filename)
                    .chompPrefix(n.basedir)
                    .replace(dirSeparator, "::")
                    .chompPrefix("::")
                    ~ "::" ~ baseName(filename, ".xml");
            }
        }
        //dfmt on
        return "";
    }

    Types getTypes(Element types, string curr_ns) {
        import std.stdio;
        import std.conv;
        import std.typecons;

        Types xml_types;
        foreach (Element elem; types.elements) {
            final switch (elem.tag.name) {
            case "SubType":
                SubType subtype = SubType(elem.tag.attr["name"], elem.tag.attr["type"], curr_ns);
                if (auto minVal = "min" in elem.tag.attr) {
                    subtype.min = *minVal;
                }

                if (auto maxVal = "max" in elem.tag.attr) {
                    subtype.max = *maxVal;
                }

                if (auto unit = "unit" in elem.tag.attr) {
                    subtype.unit = *unit;
                }
                xml_types.subtypes ~= subtype;
                break;

            case "Record":
                Record rec = Record(elem.tag.attr["name"], curr_ns);
                foreach (Element variable; elem.elements) {
                    Variable var = Variable(variable.tag.attr["name"], variable.tag.attr["type"]);
                    
                    if (auto minVal = "min" in variable.tag.attr) {
                        var.min = *minVal;
                    }

                    if (auto maxVal = "max" in variable.tag.attr) {
                        var.max = *maxVal;
                    }

                    if (auto defaultVal = "defaultValue" in variable.tag.attr) {
                        var.defaultVal = *defaultVal;
                    }
                    rec.variables[variable.tag.attr["name"]] = var;
                }
                xml_types.record ~= rec;
                break;
            case "Enum":
                Enum enums = Enum(elem.tag.attr["name"], curr_ns);
                Nullable!int min;
                Nullable!int max;
                int val, enumcount = 0;
                foreach (Element enumitem; elem.elements) {
                    if(auto val_ = "value" in enumitem.tag.attr) {
                        val = to!int(*val_);
                    } else {
                        val = enumcount;
                        enumcount++;
                    }

                    if (min.isNull && max.isNull) {
                            min = val;
                            max = val;
                    } else if (max < val) {
                        max = val;
                    } else if (min > val) {
                        min = val;
                    }

                    enums.enumitems ~= EnumItem(enumitem.tag.attr["name"],
                        to!string(val));
                }
                enums.min = to!string(min);
                enums.max = to!string(max);
                xml_types.enums ~= enums;
                break;
            case "Primitive":
                Primitive prim = Primitive(elem.tag.attr["name"],
                    elem.tag.attr["type"], elem.tag.attr["size"]);
                prim.cppint = CPPInterface(elem.elements[0].tag.attr["header"]);
                xml_types.prims ~= prim;
                break;
            }
        }
        return xml_types;
    }

    auto getContinousInterface(Element interface_elem) {
        import std.algorithm : canFind;
        Interface_ ret;
        ContinousInterface cis;
        //Add more interfaces here
        cis.name = interface_elem.tag.attr["name"];
        cis.direction = interface_elem.tag.attr["direction"] == "From_Provider"
            ? Direction.from : Direction.to;
        foreach (Element elem; interface_elem.elements) {
            switch (elem.tag.name) {
            case "DataItem":
                DataItem di = getDataItem(elem);
                if(!cis.data_items.canFind(di))
                    cis.data_items ~= getDataItem(elem);
                break;
            case "MonitoredItem":
                cis.mon_items ~= getMonitoredItem(elem);
                break;
            default:
                break;
            }
        }

        return cis;
    }

    auto getDataItem(Element ditem_elem) {
        DataItem data_item = DataItem(ditem_elem.tag.attr["name"], ditem_elem.tag.attr["type"]);
        if (auto defaultVal = "defaultValue" in ditem_elem.tag.attr) {
            data_item.defaultVal = *defaultVal;
        }

        if (auto startupVal = "startupValue" in ditem_elem.tag.attr) {
            data_item.startupVal = *startupVal;
        }

        return data_item;
    }

    auto getMonitoredItem(Element mitem_elem) {
        MonitoredItem mon_item = MonitoredItem(mitem_elem.tag.attr["name"], mitem_elem.tag.attr["type"]);
        if (auto defaultVal = "defaultValue" in mitem_elem.tag.attr) {
            mon_item.defaultVal = *defaultVal;
        }

        if (auto startupVal = "startupValue" in mitem_elem.tag.attr) {
            mon_item.startupVal = *startupVal;
        }

        return mon_item;
    }

    auto getEventGroupInterface(Element interface_elem) {
        Interface_ ret;
        EventGroupInterface eis;
        eis.name = interface_elem.tag.attr["name"];
        eis.direction = interface_elem.tag.attr["direction"] == "From_Provider"
            ? Direction.from : Direction.to;
        foreach (Element elem; interface_elem.elements) {
            switch (elem.tag.name) {
                case "Event":
                    Event event = Event(elem.tag.attr["name"]);
                    foreach(item_elem ; elem.elements) {
                        switch(item_elem.tag.name) {
                            case "DataItem": 
                                event.data_items ~= getDataItem(item_elem);
                                break;
                            default:
                                break;
                        }
                    }
                    eis.events ~= event;
                    break;
                default:
                    break;
            }
        }
        return eis;
    }

    Types[] types(Document doc, string curr_ns) {
        if (doc.tag.name == "Types") { //Everything is a type!
            if (curr_ns.endsWith("::types")) {
                curr_ns = curr_ns[0..$-("::types").length];
            }
            return [getTypes(doc, curr_ns)];
        } else {
            return doc.elements.filter!(a => a.tag.name == "Types").map!(a => getTypes(a, curr_ns)).array;
        }
    }

    Nullable!Interface_ interfaces(Document doc) {
        Nullable!Interface_ ret;
        if (doc.tag.name != "Interface") {
            return ret;
        } else {
            ret = Interface_();
            foreach (Element elem; doc.elements) {
                switch (elem.tag.name) {
                case "ContinuousInterface":
                    ret.ci ~= getContinousInterface(elem);
                    break;
                case "EventGroupInterface":
                    ret.ei ~= getEventGroupInterface(elem);
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
        foreach (Types old_types; old) {
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
        if(old.ci != new_.ci)
            new_.ci = old.ci ~ new_.ci;

        return new_;
    }

public:
    this(BaseDir[] bdir) {
        basedir = bdir;
        foreach(dir ; bdir) {
            xml_files ~= () @trusted { return (dirEntries(dir.basedir, "*.xml", SpanMode.breadth)
                                        .filter!(a => a.isFile)).map!(a => a.name).array; } ();
        }

        foundNamespaces = xml_files.map!(a => namespace(a)).filter!(a => a != "").array;

        nsps = parseBaseDir;

    }

    Namespace[string] parseBaseDir() {
        Namespace[string] namespaces;
        Global glob;
        foreach (string xml_file; xml_files) {
            string curr_ns = namespace(xml_file);
            logger.info("Reading XML file: " ~ xml_file);
            string doc_raw = std.file.readText(xml_file);
            auto doc = () @trusted {return new Document(doc_raw); } ();
            logger.info("XML read correctly");
            Types ntypes = merge(types(doc, curr_ns));
            Nullable!Interface_ ifaces = interfaces(doc);

            if (curr_ns == "global::types") {
                namespaces["global"] = Namespace("global", ntypes, Interface_());
                glob.enums = ntypes.enums ~ glob.enums;
                glob.prims = ntypes.prims ~ glob.prims;
                glob.record = ntypes.record ~ glob.record;
                glob.subtypes = ntypes.subtypes ~ glob.subtypes;

                continue;
            }
            if (ifaces.isNull) {
                namespaces[curr_ns] = Namespace(curr_ns, ntypes, Interface_()); //Add nullable to interface_ as standard?
                continue;
            }
            foreach (ContinousInterface c; ifaces.ci) {
                string tmp_ns = curr_ns;
                if (auto ns = tmp_ns in namespaces) {
                    namespaces[tmp_ns].ns_types = merge(ntypes, ns.ns_types);
                    namespaces[tmp_ns].interfaces = merge(ifaces, ns.interfaces);
                } else {
                    namespaces[tmp_ns] = Namespace(tmp_ns, ntypes, ifaces);
                }
            }

            foreach (EventGroupInterface c; ifaces.ei) {
                string tmp_ns = curr_ns;
                if (auto ns = tmp_ns in namespaces) {
                    namespaces[tmp_ns].ns_types = merge(ntypes, ns.ns_types);
                    namespaces[tmp_ns].interfaces = merge(ifaces, ns.interfaces);
                } else {
                    namespaces[tmp_ns] = Namespace(tmp_ns, ntypes, ifaces);
                }
            }
        }

        foreach (Namespace ns; namespaces) {
            ns.ns_types.glob = glob;
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
        if (auto ns = ns_spl.join("::") in getNamespaces) {
            out_types = merge(ns.ns_types, out_types);
            return traverseNamespace(ns_spl[0 .. $ - 1].join("::"), out_types);
        } else if (auto ns = ns_spl.join("::") ~ "::types" in getNamespaces) {
            out_types = merge(ns.ns_types, out_types);
            return traverseNamespace(ns_spl[0 .. $ - 1].join("::"), out_types);
        } else if (ns_spl.length >= 1) {
            return traverseNamespace(ns_spl[0 .. $ - 1].join("::"), out_types);
        }

        if (auto ns = "global" in getNamespaces) {
            return merge(ns.ns_types, out_types);
        }
        return out_types;
    }

    string[string] findMinMax(string topns, string type_name, DataItem ditem) {
        string[string] ret;
        Types out_types = Types();
        out_types = traverseNamespace(topns, out_types);

        foreach (SubType t; out_types.subtypes) {
            if (t.name == type_name) {
                ret["defVal"] = ditem.defaultVal;
                ret["min"] = t.min;
                ret["max"] = t.max;
                ret["type"] = "SubType";
                ret["namespace"] = t.namespace;
                return ret;
            }
        }
        foreach (Enum t; out_types.enums) {
            if (t.name == type_name) {
                ret["defVal"] = "";
                ret["min"] = t.min;
                ret["max"] = t.max;
                ret["type"] = "Enum";
                ret["namespace"] = t.namespace;
                return ret;
            }
        }
        foreach (Record t; out_types.record) {
            if (t.name == type_name) {
                ret["defVal"] = "";
                ret["min"] = "fun";
                ret["max"] = "fun";
                ret["namespace"] = t.namespace;
                ret["type"] = "Record";
                return ret;
            }
        }

        return ret;
    }

    Variable[string] findVariables(string ns, string type_name) {
        Variable[string] ret;
            Types out_types = Types();
        if (auto nsp = ns in getNamespaces()) {
            out_types = nsp.ns_types;
        }
        else if (auto nsp = ns~"::types" in getNamespaces()) {
            out_types = nsp.ns_types;
        } 
        foreach (Record t; out_types.record) {
            if (t.name == type_name) {
                ret = t.variables;
                return ret;
            }
        }
        return ret;
    }
    
}

version (none) {
    int main() {
        Types out_t = Types();
        xml_parse xml_p = new xml_parse(BaseDir("sut_unittest/namespaces"));
        xml_p.traverseNamespace("foo::bar::requirer", out_t);
        foreach (a; out_t.subtypes) {
            writeln(a);
        }

        return 0;
    }

}
