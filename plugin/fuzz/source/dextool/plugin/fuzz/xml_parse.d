module xml_parse;

import std.algorithm;
import std.array;
import std.container.array;
import std.file;
import std.path;
import std.string;
import std.xml;

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

struct ContinuesInterface {
    int direction; //From = 0; To = 1;
    auto data_items = Array!DataItem();
}

struct Interface {
    ContinuesInterface ci;
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
    Array!Interface interfaces;
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

        string namespace(string filename) {
        ///TODO: Namespaces should probably only be added if there is any interface in the file
        //dfmt off
            return dirName(filename)
                .chompPrefix(this.basedir)
                .replace(dirSeparator, "::")
                .chompPrefix("::")
                ~ "::" ~ baseName(filename, ".xml");
        //dfmt on
        }

        Types getTypes(Element types) {
            import std.stdio;
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
                        foreach(Element enumitem ; elem.elements) {
                            enums.enumitems.insertBack(EnumItem(enumitem.tag.attr["name"],
                                enumitem.tag.attr["value"]));
                        }
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

        Types[] types(Document doc) {
            if (doc.tag.name == "Types") { //Everything is a type!
                return [getTypes(doc)];
            } else {
                return doc.elements.filter!(a => a.tag.name == "Types").map!(a => getTypes(a)).array;
            }
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

        Types merge(Types old, Types new_) {
            new_.enums = old.enums ~ new_.enums;
            new_.prims = old.prims ~ new_.prims;
            new_.record = old.record ~ new_.record;
            new_.subtypes = old.subtypes ~ new_.subtypes;

            return new_;
        }

public:
    this(BaseDir bdir)
    {
        basedir = bdir;
        xml_files = (dirEntries(this.basedir, "*.xml", SpanMode.breadth).filter!(a => a.isFile)).map!(a => a.name)
            .array;
        foundNamespaces = xml_files.map!(a => namespace(a)).filter!(a => a!= "").array;
    }

    void parseBaseDir() {
        Types[string] namespaces;
        Global glob;
        foreach(string xml_file ; xml_files) {
            string curr_ns = namespace(xml_file);
            auto doc = new Document(cast(string) std.file.read(xml_file));
            Types ntypes = merge(types(doc));

            //This should be merge()
            if (curr_ns == "global::types") {
                glob.enums = ntypes.enums ~ glob.enums;
                glob.prims = ntypes.prims ~ glob.prims;
                glob.record = ntypes.record ~ glob.record;
                glob.subtypes = ntypes.subtypes ~ glob.subtypes;

                continue;
            }

            if (namespaces.get(curr_ns, Types()) != Types()) {
                namespaces[curr_ns] = merge(ntypes, namespaces[curr_ns]);
            } else {
                namespaces[curr_ns] = ntypes;
            }
        }

        foreach (string key ; namespaces.byKey) {
            namespaces[key].glob = glob;
        }
    }
}


int main() {
    xml_parse xml_p = new xml_parse(BaseDir("sut_unittest/namespaces"));
    xml_p.parseBaseDir;

    return 0;
}