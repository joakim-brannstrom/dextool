module dextool.plugin.mutate.backend.report.html.page_tree_map;

import std.json : JSONValue;
import arsd.dom : Document, Element, require, Table, RawSource;

import dextool.plugin.mutate.backend.report.html : FileIndex;
import dextool.plugin.mutate.backend.report.html.tmpl : tmplBasicPage;

/* 
* A JSON-like object that is more easily manipulated than JSONValue.
* Has operator overloads for "index", "index assign" and "in" allowing the children list to be private
* and cleaner construction of the object. 
*/
class JSONLike {
    string name;
    private JSONLike[string] children;
    long locs = -1;
    double score = -1;

    JSONValue toJSONValue() {
        JSONValue root = ["name" : name];

        if (children.length) {
            JSONValue[] descendants = [];
            foreach (c; children) {
                descendants ~= c.toJSONValue();
            }
            root.object["children"] = JSONValue(descendants);
        }
        if (locs != -1)
            root.object["locs"] = JSONValue(locs);

        if (score != -1)
            root.object["score"] = JSONValue(score);

        return root;
    }

    JSONLike opIndex(string i) pure nothrow {
        return children[i];
    }

    JSONLike opIndexAssign(JSONLike value, string i) pure nothrow {
        children[i] = value;
        return value;
    }

    bool opBinaryRight(string op)(string a) {
        if (op == "in") {
            if (a in children)
                return true;
            return false;
        }
        return false;
    }

}

@trusted auto makeTreeMapJSON(FileIndex[] files) {
    import std.array : array;
    import std.path : pathSplitter;

    auto iRoot = new JSONLike();
    iRoot.name = "root";

    foreach (f; files) {
        auto path = pathSplitter(f.display);
        auto parent = iRoot;
        foreach (seg; path) {
            if (seg !in parent) {
                auto child = new JSONLike();
                child.name = seg;
                parent[seg] = child;
            }
            parent = parent[seg];
        }
        parent.locs = f.totalMutants;
        parent.score = cast(double) f.killedMutants / cast(double) f.totalMutants;
    }
    return iRoot.toJSONValue().toPrettyString();
}

auto makeTreeMapPage(FileIndex[] files) {
    import std.format : format;

    auto doc = tmplBasicPage;
    doc.mainBody.setAttribute("onload", "init()");
    auto s = doc.root.childElements("head")[0].addChild("script");
    s.addChild(new RawSource(doc, import("d3.min.js")));
    auto container = doc.mainBody.addChild("div");
    auto s2 = doc.mainBody.addChild("script");
    s2.addChild(new RawSource(doc, format("const g_indata = %s", makeTreeMapJSON(files))));
    s2.addChild(new RawSource(doc, import("treemap.js")));
    container.setAttribute("id", "container");

    return doc.toPrettyString;
}
