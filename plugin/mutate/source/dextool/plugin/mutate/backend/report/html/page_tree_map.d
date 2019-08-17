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
auto makeTreeMapPage(FileIndex[] files) {
    import std.format : format;

    auto doc = tmplBasicPage;
    doc.mainBody.setAttribute("onload", "init()");

    auto s = doc.root.childElements("head")[0].addChild("script");
    s.addChild(new RawSource(doc, import("d3.min.js")));

    auto container = doc.mainBody.addChild("div");
    container.setAttribute("id", "container");

    auto s2 = doc.mainBody.addChild("script");
    s2.addChild(new RawSource(doc, format("const g_indata = %s", makeTreeMapJSON(files))));
    s2.addChild(new RawSource(doc, import("treemap.js")));

    return doc.toPrettyString;
}

private:

auto makeTreeMapJSON(FileIndex[] files) {
    import std.array : array;
    import std.path : pathSplitter;

    auto root = new JSONLike();
    root.name = "root";

    foreach (f; files) {
        auto path = pathSplitter(f.display);
        auto parent = root;
        foreach (seg; path) {
            if (seg !in parent) {
                auto child = new JSONLike();
                child.name = seg;
                parent[seg] = child;
            }
            parent = parent[seg];
        }
        parent.locs = f.totalMutants;
        if (f.totalMutants == 0)
            parent.score = 1.0;
        else
            parent.score = cast(double) f.killedMutants / cast(double) f.totalMutants;
    }
    return root.toJSONValue().toPrettyString();
}

class JSONLike {
    import std.array : empty;
    import std.format : format;
    import std.typecons : Nullable;

    string name;
    private JSONLike[string] children;
    Nullable!long locs;
    Nullable!double score;

    JSONValue toJSONValue() {
        JSONValue root = ["name" : name];

        if (!children.empty) {
            JSONValue[] descendants = [];
            foreach (c; children) {
                descendants ~= c.toJSONValue();
            }
            root.object["children"] = JSONValue(descendants);
        }
        if (!locs.isNull)
            root.object["locs"] = JSONValue(locs.get);

        if (!score.isNull)
            root.object["score"] = JSONValue(format("%.2s", score.get));

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
        static if (op == "in") {
            if (a in children) {
                return true;
            }
            return false;
        } else
            static assert(0, "Operator " ~ op ~ " not implmeneted");
    }
}
