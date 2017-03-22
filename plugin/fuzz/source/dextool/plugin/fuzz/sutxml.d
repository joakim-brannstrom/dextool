Building package dfmt in /home/tmp/.dub/packages/dfmt-0.5.0-beta4/dfmt/
Performing "debug" build using dmd for x86_64.
libdparse 0.7.0: target for configuration "library" is up to date.
dfmt 0.5.0-beta4: target for configuration "application" is up to date.
To force a rebuild of up-to-date targets, run again with --force.
Running ../../../../../../../../.dub/packages/dfmt-0.5.0-beta4/dfmt/dfmt sutxml.d
/*
    This will be changed to something else. This file should be considered a POC until this changes. 
TODO: Should be more modular.
*/

module test;

import std.string;
import std.file;
import std.path;
import std.algorithm;
import std.stdio;
import std.array;
import std.container.array;
import std.xml;

//string[] interfaces =  ["ContinuesInterface"]; //Monitored and Event should probl. be added here

struct XMLType {
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

@safe struct SutEnvironment {
private:
    Document doc;
    string basedir;
    string[] foundNamespaces;
    string[] xmlinterfaces;
    Array!XMLType[string] xmltypes;

    string namespace(string filename) {
        //dfmt off
            return dirName(filename)
                    .chompPrefix(this.basedir)
                    .replace(dirSeparator, "::")
                    .chompPrefix("::")
                    .chomp("::");
            //dfmt on
    }

    @trusted Array!XMLType getAllSubtypes(Element types) { //Types = Types tag
        Array!XMLType xml_types;
        foreach (Element subtype; types.elements) {
            XMLType curr_type = XMLType(subtype.tag.attr["name"], subtype.tag.attr["type"]);

            if (subtype.tag.attr.get("min", "-1NOTFOUND") != "-!NOTFOUND") {
                curr_type.min = subtype.tag.attr["min"];
            }

            if (subtype.tag.attr.get("max", "-1NOTFOUND") != "-1NOTFOUND") {
                curr_type.max = subtype.tag.attr["max"];
            }

            if (subtype.tag.attr.get("unit", "-1NOTFOUND") != "-1NOTFOUND") {
                curr_type.unit = subtype.tag.attr["unit"];
            }

            xml_types.insertBack(curr_type);
        }

        return xml_types;
    }

    @trusted bool checkInterface(string filename) {
        auto fileinterfacename = baseName(filename, ".xml");

        if (doc.tag.name != "Interface") {
            writeln("WARNING: Cannot find interface tag");
            return false;
        }

        immutable string interfacename = doc.tag.attr["name"];

        if (interfacename != fileinterfacename) {
            writefln("WARNING: Interface name is incorrect! Was looking for '%s', found '%s'",
                    fileinterfacename, interfacename);
            return false;
        }

        return true;
    }

    @trusted void iinterfaces(string filename, Element iface_type) { /// tag = among(interfaces);
        if (!initDocument(filename) || !checkInterface(filename)) {
            return;
        }

        //if (iface_type.tag.name == "ContinuesInterface") { // Better solution here is required
        ContinuesInterface ciface;
        //}
        foreach (Element xml_interface; iface_type.elements) {
            if (xml_interface.tag.name == "DataItem") { /// Ignore the rest
                DataItem data_item = DataItem(xml_interface.tag.attr["name"],
                        xml_interface.tag.attr["type"]);
                if (xml_interface.tag.attr.get("defaultValue", "-1NOTFOUND") != "-1NOTFOUND") {
                    data_item.defaultVal = xml_interface.tag.attr["defaultValue"];
                }

                if (xml_interface.tag.attr.get("startupValue", "-1NOTFOUND") != "-1NOTFOUND") {
                    data_item.startupVal = xml_interface.tag.attr["startupValue"];
                }

                ciface.data_items.insertBack(data_item);
            }
        }
    }

    @trusted bool initDocument(string filename) {
        string s = cast(string) std.file.read(filename);
        if (s.length == 0)
            return false;

        doc = new Document(s);

        return true;
    }

    @trusted void types(string filename) {
        if (!initDocument(filename) || !checkInterface(filename)) {
            return;
        }
        foreach (Element elem; doc.elements.filter!(a => a.tag.name == "Types"
                || a.tag.name.among("ContinuesInterface"))) {
            if (elem.tag.name == "Types") {
                writeln(getAllSubtypes(elem));
            } else {
                //Handle interfaces

            }
        }
    }

public:
    @trusted this(string basedir) {
        this.basedir = basedir.chomp(dirSeparator);
        xmlinterfaces = (dirEntries(this.basedir, "*.xml", SpanMode.breadth).filter!(a => a.isFile)).map!(a => a.name)
            .array;
        foundNamespaces = xmlinterfaces.map!(a => namespace(a)).array;
    }

    string[] getAllNamespaces() {
        return this.foundNamespaces;
    }

    string[] getAllXMLInterfaces() {
        return this.xmlinterfaces;
    }

    void getTypesFromInterfaces() {
        foreach (string d; xmlinterfaces) {
            types(d);
        }
    }
}

int main() {
    import std.stdio;

    writeln(SutEnvironment("./xmltest/").getAllNamespaces);
    writeln(SutEnvironment("./xmltest").getAllXMLInterfaces);

    SutEnvironment(".").getTypesFromInterfaces;

    return 0;
}
