module test;

import std.string;
import std.file;
import std.path;
import std.algorithm;
import std.stdio;
import std.array;
import std.container.array;

struct BaseDir {
    string basedir;
    this (string base) { basedir = base; }
    string toString() { return basedir; }
    alias basedir this;
}

struct Namespace {

}
@safe struct SutEnvironment {
    private:
        string basedir;
        string[] foundNamespaces;
        string[] xmlinterfaces;

        string namespace(string filename) {
            //dfmt off
            return dirName(filename)
                    .replace(this.basedir, "")
                    .replace(dirSeparator, "::")
                    .chompPrefix("::")
                    .chomp("::");
            //dfmt on
        }

    public:
        @trusted this(string basedir) {
            this.basedir = basedir;
            xmlinterfaces = (dirEntries(this.basedir, "*.xml", SpanMode.breadth).filter!(a => a.isFile)).map!(a=>a.name).array;
            foundNamespaces = xmlinterfaces.map!(a => namespace(a)).array;
        }


        string[] getAllNamespaces() { return this.foundNamespaces; }
        string[] getAllXMLInterfaces() { return this.xmlinterfaces; }

}


int main() {
    import std.stdio;

    writeln(SutEnvironment(".").getAllNamespaces);
    writeln(SutEnvironment(".").getAllXMLInterfaces);

    return 0;
}