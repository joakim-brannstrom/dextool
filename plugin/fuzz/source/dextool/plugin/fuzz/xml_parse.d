module xml_parse;

struct BaseDir {
    string basedir;
    alias basedir this;
}

struct Types {
    Array!Primitive prims;
    Array!SubType subtypes;
    Array!Record record;
}

struct Record {
    string name;
    Variable[string] records;
}

struct Variable {
    string name;
    string type;
}

struct Enum {
    Array!EnumItem enumitems;
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
            if (!initDocument(filename) || !checkInterface(filename)) {
                return "";
            }
            return dirName(filename)
                .chompPrefix(this.basedir)
                .replace(dirSeparator, "::")
                .chompPrefix("::")
                ~ "::" ~ baseName(filename, ".xml");
        //dfmt on
        }

public:
    this(BaseDir bdir)
    {
        basedir = bdir;
        xml_files = (dirEntries(this.basedir, "*.xml", SpanMode.breadth).filter!(a => a.isFile)).map!(a => a.name)
            .array;
        foundNamespaces = xmlinterfaces.map!(a => namespace(a)).filter!(a => a!= "").array;
    }

    void parseBaseDir() {
        foreach(string xml_file ; xml_files) {
            string curr_ns = namespace(xml_file);
            auto doc = new Document(cast(string) std.file.read(xml_file));

        }
    }


}
