// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module plugin.backend.plantuml;

import std.meta : templateAnd, templateOr;
import std.range : ElementType;
import std.typecons : Typedef, Tuple, Flag, Yes, No;
import logger = std.experimental.logger;

import dsrcgen.plantuml;

import application.types;
import cpptooling.analyzer.type : USRType, TypeKindAttr;
import cpptooling.analyzer.clang.ast.visitor : Visitor;
import cpptooling.data.type : CxParam, CxReturnType, TypeKindVariable;
import cpptooling.data.symbol.types : FullyQualifiedNameType;
import cpptooling.analyzer.clang.analyze_helper : ClassDeclResult;

static import cpptooling.data.class_classification;

version (unittest) {
    import test.helpers : shouldEqualPretty;
    import unit_threaded : Name, shouldEqual;
} else {
    private struct Name {
        string name_;
    }
}

/** Control various aspectes of the analyze and generation like what nodes to
 * process.
 */
interface Controller {
@safe:
    /// Query the controller with the filename of the AST node for a decision
    /// if it shall be processed.
    bool doFile(in string filename, in string info);

    /** Determine by checking the filesystem if a templated PREFIX_style file shall be created.
     *
     * Create it with a minimal style.
     * Currently just the direction but may change in the future.
     */
    Flag!"genStyleInclFile" genStyleInclFile();

    /// Strip the filename according to user regex.
    FileName doComponentNameStrip(FileName fname);
}

/// Parameters used during generation.
/// Important aspact that they do NOT change, therefore it is pure.
pure const interface Parameters {
@safe:
    import std.typecons : Tuple, Flag;

    alias Files = Tuple!(FileName, "classes", FileName, "components", FileName,
            "styleIncl", FileName, "styleOutput");

    /// Output directory to store files in.
    DirName getOutputDirectory();

    /// Files to write generated diagram data to.
    Files getFiles();

    /// Name affecting filenames.
    FilePrefix getFilePrefix();

    /** In all diagrams generate an "!include" of the style file.
     *
     * If the file PREFIX_style do not exist, create it with a minimal style.
     * Currently just the direction but may change in the future.
     */
    Flag!"doStyleIncl" doStyleIncl();

    /// Generate a dot graph in the plantuml file
    Flag!"doGenDot" doGenDot();

    /// If class methods should be part of the generated class diagrams.
    Flag!"genClassMethod" genClassMethod();

    /// If the parameters of methods should result in directed association.
    Flag!"genClassParamDependency" genClassParamDependency();

    /// If the inheritance hierarchy between classes is generated.
    Flag!"genClassInheritDependency" genClassInheritDependency();

    /// If the class members result in dependency on those members.
    Flag!"genClassMemberDependency" genClassMemberDependency();
}

/// Data produced by the generator like files.
interface Products {
@safe:
    /** Data pushed from the generator to be written to files.
     *
     * The put value is the code generation tree. It allows the caller of
     * Generator to inject more data in the tree before writing. For example a
     * custom header.
     *
     * Params:
     *   fname = file the content is intended to be written to.
     *   data = data to write to the file.
     */
    void putFile(FileName fname, PlantumlRootModule data);

    /// ditto.
    void putFile(FileName fname, PlantumlModule data);

    /// Dummy to make the interface structurally compatible with cppvariant.Products
    void putLocation(FileName loc, LocationType type);
}

/** Relations to targets with count and kind.
 *
 * Intented to be used in a hashmap with the key as the "from".
 */
private struct Relate {
@safe:
    alias Key = USRType;

    enum Kind {
        None,
        Extend,
        Compose,
        Aggregate,
        Associate,
        Relate
    }

    private alias Inner = Tuple!(uint, "count", Kind, "kind");
    private Inner[][Key] to;

    /// Returns: number of outgoing connections
    size_t fanOut() pure nothrow const {
        return to.length;
    }

    void put(Key to_, Kind kind)
    out {
        assert(to_ in to);
    }
    body {
        auto v = to_ in to;
        if (v is null) {
            to[to_] = Inner[].init;
            v = to_ in to;
        }

        // ugly algorithm, use an inner hashmap instead
        bool is_new = true;
        foreach (ref r; *v) {
            if (r.kind == kind) {
                r.count++;
                is_new = false;
                break;
            }
        }

        if (is_new) {
            *v ~= Inner(1, kind);
        }
    }

    /** A range of the form FROM-TO with metadata.
     *
     * count is the total number of outgoing connections to the target.
     * For example would 2 Relation and 4 Extend result in the sum of 6.
     */
    auto toRange(const Relate.Key from) pure const @trusted {
        import std.algorithm : map;
        import std.array : array;

        alias RelateTuple = Tuple!(Relate.Key, "from", Relate.Key, "to", ulong, "count");

        static ulong sumFanOut(const(Inner)[] inner) pure {
            import std.algorithm : sum;

            return inner.map!(a => a.count).sum;
        }

        // dfmt off
        return to.byKeyValue.map!(a => RelateTuple(from, a.key, sumFanOut(a.value)))
            .array();
        // dfmt on
    }

    /// Convert the TO/value store to a FROM-KIND-TO-COUNT array.
    auto toFlatArray(const Relate.Key from) pure const @trusted {
        import std.algorithm : filter, map, joiner;
        import std.array : array;

        alias RelateTuple = Tuple!(Relate.Key, "from", Kind, "kind",
                Relate.Key, "to", uint, "count");

        // dfmt off
        return to.byKeyValue.map!(a => a.value
                                    .filter!(b => b.kind != Kind.None)
                                    .map!(b => RelateTuple(from, b.kind, a.key, b.count))
                                    .array())
            .joiner()
            .array();
        // dfmt on
    }

    auto toStringArray(const Relate.Key from) pure const @trusted {
        import std.algorithm : map;
        import std.conv : text;
        import std.format : format;
        import std.array : array;

        // dfmt off
        return this.toFlatArray(from)
            .map!(b => format("%s -%s- [%d]%s", cast(string) b.from, text(b.kind), b.count, cast(string) b.to))
            .array();
        // dfmt on
    }
}

private size_t[] nameIndexSortedRange(T, alias sortNameBy)(T arr) pure {
    import std.algorithm : makeIndex;

    auto index = new size_t[arr.length];

    makeIndex!((a, b) => sortNameBy(a) < sortNameBy(b))(arr, index);
    return index;
}

private auto nameSortedRange(T, alias sortNameBy)(const T t) pure {
    import std.algorithm : map;
    import std.array : array;

    auto arr = t.asArray();
    auto index = nameIndexSortedRange!(typeof(arr), sortNameBy)(arr);

    return index.map!(i => arr[i]).array();
}

private auto fanOutSorted(T)(T t) pure {
    import std.algorithm : makeIndex, map;
    import std.array : array;

    //TODO how to avoid doing this allocation?

    auto arr = t.nameSortedRange();
    auto fanout_i = new size_t[arr.length];

    makeIndex!((a, b) => t.relate_to[cast(
            Relate.Key) a[0]].fanOut > t.relate_to[cast(Relate.Key) b[0]].fanOut)(arr, fanout_i);

    return fanout_i.map!(i => arr[i]).array();
}

/** UML Class Diagram.
 *
 * Not designed for the general case.
 * The design is what the plantuml plugin needs when analyzing more than one
 * file. This is the container that is then passed between the analyze stages.
 *
 * All classes must exist in "classes".
 * It is common that during data gathering a CppClass is found to be related to
 * another class by a FullyQualifiedNameType so the relation is added before
 * the class represented by the FullyQualifiedNameType is added.
 *
 * A --> B
 * Directed relation.
 * A can have many connections to B.
 *
 * Store of R[A.B].
 * When analyzing the structural data it is this kind of relations that are
 * found. From a CppClass to many X, where X is other CppClass.
 * The key used must be unique, thus the choice of using fully qualified name.
 *
 * Example of relations.
 * A --> B (member)
 * A --> B (member)
 * A --> B (inherit)
 * B --> A (member)
 *
 * relate[A].put(B, Compose)
 * relate[A].put(B, Compose)
 * relate[A].put(B, Extend)
 * relate[B].put(A, Compose)
 *
 * The relations are of the kind Fan-out.
 */
class UMLClassDiagram {
@safe:
    alias ClassClassificationState = cpptooling.data.class_classification.State;

    alias Key = Typedef!(string, string.init, "UMLKey");
    alias DisplayName = Typedef!(string, string.init, "DisplayName");

    struct Class {
        DisplayName displayName;
        ClassClassificationState classification;
        string[] content;
    }

    /// The class is only added if it doesn't already exist in the store.
    void put(Key key, DisplayName display_name) {
        if (key !in classes) {
            classes[key] = Class(display_name);
            relate_to[cast(Relate.Key) key] = Relate.init;
        }
    }

    void put(Key key, string content)
    in {
        assert(key in classes);
    }
    body {
        classes[key].content ~= content;
    }

    void put(Key key, ClassClassificationState classification)
    in {
        assert(key in classes);
    }
    body {
        classes[key].classification = classification;
    }

    /** Add a relation between two classes and increase the count on the class
     * related TO.
     */
    void relate(Key from, Key to, DisplayName display_name, Relate.Kind kind)
    out {
        assert(from in classes);
        assert(to in classes);
        assert(kind != Relate.Kind.None);
    }
    body {
        put(to, display_name);
        relate_to[cast(Relate.Key) from].put(cast(Relate.Key) to, kind);
    }

    const(Relate) relateTo(Key k) pure const
    in {
        assert(k in classes);
        assert((cast(Relate.Key) k) in relate_to);
    }
    body {
        return relate_to[cast(Relate.Key) k];
    }

    /// Return: Flat array of all relations of type FROM-KIND-TO-COUNT.
    auto relateToFlatArray() pure const @trusted {
        import std.algorithm : map, joiner;
        import std.array;

        return relate_to.byKeyValue.map!(a => a.value.toFlatArray(a.key)).joiner().array();
    }

    alias KeyClass = Tuple!(Key, const(Class));

    KeyClass[] asArray() const pure nothrow @trusted {
        import std.array : array;
        import std.algorithm : map;

        //TODO how to do this without so much generated GC

        // dfmt off
        return classes.byKeyValue
            .map!(a => KeyClass(a.key, a.value))
            .array();
        // dfmt on
    }

    auto nameSortedRange() const pure @trusted {
        static string sortClassNameBy(T)(ref T a) {
            return a[1].displayName.str;
        }

        return .nameSortedRange!(typeof(this), sortClassNameBy)(this);
    }

    private string[] classesToStringArray() const pure @trusted {
        import std.algorithm : map, joiner;
        import std.array : array;
        import std.ascii : newline;
        import std.conv : text;
        import std.format : format;
        import std.range : only, chain, takeOne;

        // dfmt off
        return classes.byKeyValue.map!(a => chain(only(format("%s -> %s%s", a.value.displayName.str, a.key.str, a.value.content.length == 0 ? "" : " {")),
                                                  a.value.content.dup.map!(b => "  " ~ b),
                                                  a.value.content.takeOne.map!(b => "} // " ~ a.value.displayName.str))
                                       .joiner(newline)
                                       .text)
            .array();
        // dfmt on
    }

    private string[] relateToStringArray() const pure @trusted {
        import std.algorithm : map, joiner;
        import std.array;

        return relate_to.byKeyValue.map!(a => a.value.toStringArray(a.key)).joiner().array();
    }

    override string toString() @safe pure const {
        import std.ascii : newline;
        import std.algorithm : joiner;
        import std.conv : text;
        import std.format : format;
        import std.range : only, chain;

        // dfmt off
        return chain(only(format("UML Class Diagram (Total %d) {",classes.length)),
                     classesToStringArray,
                     relateToStringArray,
                     only("} // UML Class Diagram"),
                     ).joiner(newline).text;
        // dfmt on
    }

    Relate[Relate.Key] relate_to;
    private Class[Key] classes;
}

/** UML Component Diagram.
 *
 * Not designed for the general case.
 * The design is what the plantuml plugin needs when analyzing more than one
 * file. This is the container that is then passed between the analyze stages.
 *
 * The relations are of the kind Fan-out.
 */
class UMLComponentDiagram {
    import std.container.rbtree : RedBlackTree;

    alias Key = Typedef!(string, string.init, "UMLKey");
    alias Location = Typedef!(string, string.init, "Location");
    alias DisplayName = Typedef!(string, string.init, "DisplayName");

    struct Component {
        DisplayName displayName;
        string[] toFile;
        RedBlackTree!Location contains;
    }

    /// The component is only added if it doesn't already exist in the store.
    void put(Key key, DisplayName display_name) @safe {
        if (key !in components) {
            components[key] = Component(display_name, null, new RedBlackTree!Location);
            relate_to[cast(Relate.Key) key] = Relate.init;
        }
    }

    /// Add a location that the component encapsulate
    void put(Key key, Location loc) @trusted
    out {
        assert(key in components);
    }
    body {
        components[key].contains.insert(loc);
    }

    /** Add a relation between two components and increase the count on the class
     * related TO.
     */
    void relate(Key from, Key to, DisplayName toDisplayName, Relate.Kind kind) @safe
    out {
        assert(from in components);
        assert(to in components);
        assert(kind != Relate.Kind.None);
    }
    body {
        put(to, toDisplayName);
        relate_to[cast(Relate.Key) from].put(cast(Relate.Key) to, kind);

        components[from].toFile ~= cast(string) to;
    }

    const(Relate) relateTo(Key k) pure const @safe
    in {
        assert(k in components);
        assert((cast(Relate.Key) k) in relate_to);
    }
    body {
        return relate_to[cast(Relate.Key) k];
    }

    /// Return: Flat array of all relations of type FROM-KIND-TO-COUNT.
    auto relateToFlatArray() pure const @trusted {
        import std.algorithm : map, joiner;
        import std.array : array;

        return relate_to.byKeyValue.map!(a => a.value.toFlatArray(a.key)).joiner().array();
    }

    alias KeyComponent = Tuple!(Key, const(Component));

    KeyComponent[] asArray() const pure nothrow @trusted {
        import std.array : array;
        import std.algorithm : map;

        //TODO how to do this without so much generated GC

        // dfmt off
        return components.byKeyValue
            .map!(a => KeyComponent(a.key, a.value))
            .array();
        // dfmt on
    }

    auto nameSortedRange() const pure @trusted {
        static string sortComponentNameBy(T)(ref T a) {
            return cast(string) a[1].displayName;
        }

        return .nameSortedRange!(typeof(this), sortComponentNameBy)(this);
    }

    private string[] componentsToStringArray() const pure @trusted {
        import std.algorithm : map, joiner;
        import std.ascii : newline;
        import std.array : array;
        import std.format : format;
        import std.typecons : tuple;

        // dfmt off
        return nameSortedRange
            .map!(a => tuple(a[0], a[1].displayName, a[1].contains[].map!(a => newline ~ "  " ~ cast(string) a).joiner))
            .map!(a => format("%s as %s%s", a[0].str,
                a[1].str,
                a[2])).array();
        // dfmt on
    }

    private string[] relateToStringArray() const pure @trusted {
        import std.algorithm : map, joiner;
        import std.array : array;

        return relate_to.byKeyValue.map!(a => a.value.toStringArray(a.key)).joiner().array();
    }

    void toString(Writer)(scope Writer w) @safe const {
        import std.algorithm : joiner, each;
        import std.ascii : newline;
        import std.format : formattedWrite;
        import std.range.primitives : put;
        import std.range : zip, repeat;

        formattedWrite(w, "UML Component Diagram (Total %d) {", components.length);
        put(w, newline);
        zip(componentsToStringArray, repeat(newline)).each!((a) {
            put(w, a[0]);
            put(w, a[1]);
        });
        zip(relateToStringArray, repeat(newline)).each!((a) {
            put(w, a[0]);
            put(w, a[1]);
        });
        put(w, "} // UML Component Diagram");
    }

    override string toString() @safe const {
        import std.exception : assumeUnique;

        char[] buf;
        buf.reserve(100);
        this.toString((const(char)[] s) { buf ~= s; });
        auto trustedUnique(T)(T t) @trusted {
            return assumeUnique(t);
        }

        return trustedUnique(buf);
    }

    Relate[Relate.Key] relate_to;
    private Component[Key] components;
}

@Name("Should be a None relate not shown and an extended relate")
unittest {
    Relate r;
    r.put(Relate.Key("B"), Relate.Kind.None);
    r.put(Relate.Key("B"), Relate.Kind.Extend);

    r.toStringArray(Relate.Key("A")).shouldEqual(["A -Extend- [1]B"]);
}

@Name("Should be all types of relates")
unittest {
    Relate r;
    r.put(Relate.Key("B"), Relate.Kind.None);
    r.put(Relate.Key("B"), Relate.Kind.Extend);
    r.put(Relate.Key("B"), Relate.Kind.Compose);
    r.put(Relate.Key("B"), Relate.Kind.Aggregate);
    r.put(Relate.Key("B"), Relate.Kind.Associate);

    r.toStringArray(Relate.Key("A")).shouldEqual(["A -Extend- [1]B",
            "A -Compose- [1]B", "A -Aggregate- [1]B", "A -Associate- [1]B"]);
}

@Name("Should be two relates to the same target")
unittest {
    Relate r;
    r.put(Relate.Key("B"), Relate.Kind.Compose);
    r.put(Relate.Key("B"), Relate.Kind.Compose);

    r.toStringArray(Relate.Key("A")).shouldEqual(["A -Compose- [2]B"]);
}

@Name("Should be a UML diagram with one class")
unittest {
    auto uml = new UMLClassDiagram;
    uml.put(UMLClassDiagram.Key("A"), UMLClassDiagram.DisplayName("A"));

    uml.toString.shouldEqualPretty("UML Class Diagram (Total 1) {
A -> A
} // UML Class Diagram");
}

@Name("Should be a UML diagram with two classes related")
unittest {
    auto uml = new UMLClassDiagram;
    auto ka = UMLClassDiagram.Key("A");
    auto kb = UMLClassDiagram.Key("B");
    uml.put(ka, UMLClassDiagram.DisplayName("A"));
    uml.put(kb, UMLClassDiagram.DisplayName("B"));

    uml.relate(ka, kb, UMLClassDiagram.DisplayName("B"), Relate.Kind.Extend);

    uml.toString.shouldEqualPretty("UML Class Diagram (Total 2) {
A -> A
B -> B
A -Extend- [1]B
} // UML Class Diagram");
}

@Name("Should be a UML Component diagram with two components related")
unittest {
    auto uml = new UMLComponentDiagram;
    auto ka = UMLComponentDiagram.Key("a");
    auto kb = UMLComponentDiagram.Key("b");
    uml.put(ka, cast(UMLComponentDiagram.DisplayName) "A");
    // shall be dedupliated
    uml.put(ka, cast(UMLComponentDiagram.Location) "file.h");
    uml.put(ka, cast(UMLComponentDiagram.Location) "file.h");

    uml.relate(ka, kb, cast(UMLComponentDiagram.DisplayName) "B", Relate.Kind.Relate);

    uml.toString.shouldEqualPretty("UML Component Diagram (Total 2) {
a as A
  file.h
b as B
a -Relate- [1]b
} // UML Component Diagram");
}

struct Generator {
    import cpptooling.data.representation : CppRoot;
    import cpptooling.data.symbol.container : Container;

    static struct Modules {
        private static postInit(ref this m) {
            m.classes_dot.suppressIndent(1);
            m.components_dot.suppressIndent(1);
        }

        import plugin.utility : MakerInitializingClassMembers;

        mixin MakerInitializingClassMembers!(Modules, postInit);

        PlantumlModule classes;
        PlantumlModule classes_dot;
        PlantumlModule components;
        PlantumlModule components_dot;
    }

    this(Controller ctrl, Parameters params, Products products) {
        this.ctrl = ctrl;
        this.params = params;
        this.products = products;
        this.uml_class = new UMLClassDiagram;
        this.uml_component = new UMLComponentDiagram;
    }

    auto process() {
        auto m = Modules.make();
        generate(uml_class, uml_component, params.doGenDot, m);
        postProcess(ctrl, params, products, m);
    }

    UMLClassDiagram uml_class;
    UMLComponentDiagram uml_component;

private:
    Controller ctrl;
    Parameters params;
    Products products;

    static void postProcess(Controller ctrl, Parameters params, Products prods, Modules m) {
        static PlantumlRootModule makeMinimalStyle(Flag!"genClassMethod" show_methods) {
            auto proot = PlantumlRootModule.make();

            auto class_ = proot.makeUml;
            class_.stmt("left to right direction");
            class_.stmt("'skinparam linetype polyline");
            class_.stmt("'skinparam linetype ortho");
            class_.stmt("set namespaceSeparator none");
            if (show_methods) {
                class_.stmt("'hide members");
            } else {
                class_.stmt("hide members");
            }

            auto component = proot.makeUml;
            component.stmt("left to right direction");
            component.stmt("skinparam componentStyle uml2");
            component.stmt("'skinparam linetype polyline");
            component.stmt("'skinparam linetype ortho");
            component.stmt("set namespaceSeparator none");
            component.stmt("hide circle");
            component.stmt("hide methods");
            component.stmt("'To hide file location");
            component.stmt("hide members");

            return proot;
        }

        enum DotLayout {
            Neato,
            Dot,
            DotOrtho
        }

        static PlantumlModule makeDotPreamble(DotLayout layout, Flag!"doSmall" doSmall) {
            auto m = new PlantumlModule;
            m.suppressIndent(1);

            //TODO if DotOrtho and Dot don't change consider removing the code
            // duplication.
            final switch (layout) with (DotLayout) {
            case Neato:
                m.stmt("layout=neato");
                m.stmt("edge [len=3]");
                break;
            case DotOrtho:
                m.stmt("layout=dot");
                m.stmt("rankdir=LR");
                m.stmt("pack=true");
                m.stmt("concentrate=true");
                // inactivating, can result in a crash as of
                // dot 2.38.0 (20140413.2041)
                m.stmt("// activate for orthogonal lines, aka straight lines");
                m.stmt("// but can result in GraphViz/dot crashing");
                m.stmt("//splines=ortho");
                break;
            case Dot:
                m.stmt("layout=dot");
                m.stmt("rankdir=LR");
                m.stmt("pack=true");
                m.stmt("concentrate=true");
                break;
            }

            m.sep(2);

            m.stmt("colorscheme=svg");
            if (doSmall) {
                m.stmt("node [style=rounded shape=box fontsize=9 width=0.25 height=0.375]");
            } else {
                m.stmt("node [style=rounded shape=box]");
            }
            m.sep(2);

            return m;
        }

        enum StyleType {
            Class,
            Component
        }

        static PlantumlModule makeStyleInclude(Flag!"doStyleIncl" do_style_incl,
                FileName style_file, StyleType style_type) {
            import std.conv : to;

            auto m = new PlantumlModule;
            if (!do_style_incl) {
                return m;
            }

            m.stmt("!include " ~ cast(string) style_file ~ "!" ~ to!string(cast(int) style_type));

            return m;
        }

        static void makeUml(Products prods, FileName fname, PlantumlModule style,
                PlantumlModule content) {
            import std.algorithm : filter;

            auto proot = PlantumlRootModule.make();
            auto c = proot.makeUml();
            c.suppressIndent(1);

            foreach (m; [style, content].filter!(a => a !is null)) {
                c.append(m);
            }

            prods.putFile(fname, proot);
        }

        static void makeDot(Products prods, FileName fname, PlantumlModule style,
                PlantumlModule content) {
            import std.algorithm : filter;
            import std.path : stripExtension, baseName;

            immutable ext_dot = ".dot";

            FileName fname_dot = (cast(string) fname).stripExtension ~ ext_dot;
            auto dot = new PlantumlModule;
            auto digraph = dot.digraph("g");
            digraph.suppressThisIndent(1);
            foreach (m; [style, content].filter!(a => a !is null)) {
                digraph.append(m);
            }
            prods.putFile(fname_dot, dot);

            auto proot = PlantumlRootModule.make();
            auto pu = proot.makeDot;
            pu.stmt("!include " ~ (cast(string) fname_dot).baseName);
            prods.putFile(fname, proot);
        }

        static FileName makeDotFileName(FileName f, DotLayout layout) {
            import std.path;

            auto ext = extension(cast(string) f);

            string suffix;
            final switch (layout) with (DotLayout) {
            case Dot:
                goto case;
            case DotOrtho:
                suffix = "_dot";
                break;
            case Neato:
                suffix = "_neato";
                break;
            }

            return FileName((cast(string) f).stripExtension ~ suffix ~ ext);
        }

        PlantumlModule style;

        if (ctrl.genStyleInclFile) {
            prods.putFile(params.getFiles.styleOutput, makeMinimalStyle(params.genClassMethod));
        }

        if (params.doGenDot) {
            makeDot(prods, makeDotFileName(params.getFiles.classes, DotLayout.Dot),
                    makeDotPreamble(DotLayout.Dot, Yes.doSmall), m.classes_dot);
            makeDot(prods, makeDotFileName(params.getFiles.classes, DotLayout.Neato),
                    makeDotPreamble(DotLayout.Neato, Yes.doSmall), m.classes_dot);
            makeDot(prods, makeDotFileName(params.getFiles.components, DotLayout.Neato),
                    makeDotPreamble(DotLayout.Neato, No.doSmall), m.components_dot);
            makeDot(prods, makeDotFileName(params.getFiles.components, DotLayout.DotOrtho),
                    makeDotPreamble(DotLayout.DotOrtho, No.doSmall), m.components_dot);
        }

        makeUml(prods, params.getFiles.classes, makeStyleInclude(params.doStyleIncl,
                params.getFiles.styleIncl, StyleType.Class), m.classes);
        makeUml(prods, params.getFiles.components, makeStyleInclude(params.doStyleIncl,
                params.getFiles.styleIncl, StyleType.Component), m.components);
    }
}

private alias ClassClassificationResult = Tuple!(TypeKindAttr, "type",
        cpptooling.data.class_classification.State, "classification");

// Unable to format the class with dfmt.
private final class UMLClassVisitor(ControllerT, ReceiveT) : Visitor {
    import std.algorithm : map, copy, each;
    import std.array : Appender;
    import std.typecons : scoped, TypedefType;

    import cpptooling.analyzer.clang.ast;
    import cpptooling.analyzer.clang.ast.visitor : generateIndentIncrDecr;
    import cpptooling.analyzer.clang.analyze_helper : analyzeClassDecl,
        analyzeConstructor, analyzeDestructor, analyzeCXXMethod,
        analyzeFieldDecl, analyzeCXXBaseSpecified, toAccessType;
    import cpptooling.data.type : MemberVirtualType;
    import cpptooling.data.representation : CppNsStack, CppNs, AccessType,
        CppAccess;
    import cpptooling.utility.clang : logNode, mixinNodeLog;

    import cpptooling.data.class_classification : ClassificationState = State;
    import cpptooling.data.class_classification : classifyClass;
    import cpptooling.data.class_classification : MethodKind;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    /** Type representation of this class.
     * Used as the source of the outgoing relations from this class.
     */
    TypeKindAttr type;

    /** Classification of the class.
     * Affected by methods.
     */
    ClassificationState classification;

    private {
        ControllerT ctrl;
        ReceiveT recv;

        Container* container;
        CppNsStack ns_stack;
        CppAccess accessType;

        /// If the class has any members.
        Flag!"hasMember" hasMember;
    }

    this(TypeKindAttr type, const(CppNs)[] reside_in_ns, ControllerT ctrl,
            ReceiveT recv, ref Container container, in uint indent) {
        this.ctrl = ctrl;
        this.recv = recv;
        this.container = &container;
        this.indent = indent;
        this.ns_stack = reside_in_ns.dup;

        this.accessType = CppAccess(AccessType.Private);
        this.classification = ClassificationState.Unknown;

        this.type = type;
    }

    /// Nested class definitions.
    override void visit(const(ClassDecl) v) @trusted {
        mixin(mixinNodeLog!());
        logger.info("class: ", v.cursor.spelling);

        auto result = analyzeClassDecl(v, *container, indent);

        if (result.type.kind.loc.kind == LocationTag.Kind.noloc
                || !ctrl.doFile(result.type.kind.loc.file, result.type.kind.loc.file)) {
            return;
        }

        recv.put(result, ns_stack);

        auto visitor = scoped!(UMLClassVisitor!(ControllerT, ReceiveT))(result.type,
                ns_stack, ctrl, recv, *container, indent + 1);
        v.accept(visitor);

        auto result_class = ClassClassificationResult(visitor.type, visitor.classification);
        recv.put(this.type, result_class);
    }

    /// Analyze the inheritance(s).
    override void visit(const(CXXBaseSpecifier) v) {
        import cpptooling.analyzer.kind : TypeKind;

        mixin(mixinNodeLog!());

        auto result = analyzeCXXBaseSpecified(v, *container, indent);
        recv.put(this.type, result);

        debug {
            import std.algorithm : each;
            import std.range : retro;
            import cpptooling.data.representation : CppInherit;

            auto inherit = CppInherit(result.name, result.access);
            retro(result.reverseScope).each!(a => inherit.put(a));

            logger.trace("inherit: ", inherit.toString);
        }
    }

    override void visit(const(Constructor) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeConstructor(v, *container, indent);
        recv.put(this.type, result, accessType);

        debug {
            auto tor = CppCtor(result.name, result.params, accessType);
            logger.trace("ctor: ", tor.toString);
        }
    }

    override void visit(const(Destructor) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeDestructor(v, *container, indent);
        classification = classifyClass(classification, MethodKind.Dtor,
                cast(MemberVirtualType) result.virtualKind, hasMember);
        recv.put(this.type, result, accessType);

        debug {
            auto tor = CppDtor(result.name, accessType, result.virtualKind);
            logger.trace("dtor: ", tor.toString);
        }
    }

    override void visit(const(CXXMethod) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeCXXMethod(v, *container, indent);
        assert(result.type.kind.loc.kind == LocationTag.Kind.loc);

        classification = classifyClass(classification, MethodKind.Method,
                cast(MemberVirtualType) result.virtualKind, hasMember);

        recv.put(this.type, result, accessType);

        debug {
            import cpptooling.data.type : CppConstMethod;
            import cpptooling.data.representation : CppMethod;

            auto method = CppMethod(result.name, result.params, result.returnType,
                    accessType, CppConstMethod(result.isConst), result.virtualKind);
            logger.trace("method: ", method.toString);
        }
    }

    override void visit(const(FieldDecl) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeFieldDecl(v, *container, indent);

        // TODO probably not necessary for classification to store it as a
        // member. Instead extend MethodKind to having a "Member".
        hasMember = Yes.hasMember;
        classification = classifyClass(classification, MethodKind.Unknown,
                MemberVirtualType.Unknown, hasMember);
        recv.put(this.type, result, accessType);

        debug {
            logger.trace("member: ", cast(string) result.name);
        }
    }

    override void visit(const(CXXAccessSpecifier) v) @trusted {
        mixin(mixinNodeLog!());
        accessType = CppAccess(toAccessType(v.cursor.access.accessSpecifier));
    }
}

final class UMLVisitor(ControllerT, ReceiveT) : Visitor {
    import std.algorithm : map, filter, cache, joiner;
    import std.range : chain, only, dropOne, ElementType;
    import std.typecons : scoped, NullableRef, TypedefType;

    import cpptooling.analyzer.clang.ast;
    import cpptooling.analyzer.clang.ast.visitor : generateIndentIncrDecr;
    import cpptooling.analyzer.clang.analyze_helper : analyzeFunctionDecl,
        analyzeVarDecl, analyzeClassDecl;
    import cpptooling.data.representation : CppNsStack, CppNs;
    import cpptooling.utility.clang : logNode, mixinNodeLog;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    private {
        ReceiveT recv;
        ControllerT ctrl;

        NullableRef!Container container;
        CppNs[] ns_stack;

    }

    this(ControllerT ctrl, ReceiveT recv, ref Container container) {
        this.ctrl = ctrl;
        this.recv = recv;
        this.container = &container;
    }

    override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(UnexposedDecl) v) {
        mixin(mixinNodeLog!());

        // An unexposed may be:

        // an extern "C"
        // UnexposedDecl "" extern "C" {...
        //   FunctionDecl "fun_c_linkage" void func_c_linkage
        v.accept(this);
    }

    override void visit(const(VarDecl) v) {
        mixin(mixinNodeLog!());

        auto result = () @trusted{ return analyzeVarDecl(v, container, indent); }();
        recv.put(result);

        debug {
            logger.info("global variable: ", cast(string) result.name);
        }
    }

    override void visit(const(FunctionDecl) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeFunctionDecl(v, container, indent);
        recv.put(result);

        debug {
            auto func = CFunction(result.name, result.params, CxReturnType(result.returnType),
                    result.isVariadic, result.storageClass, result.location);
            logger.info("global function: ", func.toString);
        }
    }

    override void visit(const(ClassDecl) v) @trusted {
        mixin(mixinNodeLog!());
        logger.info("class: ", v.cursor.spelling);

        auto result = analyzeClassDecl(v, container, indent);

        if (result.type.kind.loc.kind == LocationTag.Kind.noloc
                || !ctrl.doFile(result.type.kind.loc.file, result.type.kind.loc.file)) {
            return;
        }

        recv.put(result, ns_stack);

        auto visitor = scoped!(UMLClassVisitor!(ControllerT, ReceiveT))(result.type,
                ns_stack, ctrl, recv, container, indent + 1);
        v.accept(visitor);

        auto r_classification = ClassClassificationResult(visitor.type, visitor.classification);
        recv.put(r_classification);
    }

    override void visit(const(Namespace) v) {
        mixin(mixinNodeLog!());

        () @trusted{ ns_stack ~= CppNs(v.cursor.spelling); }();
        // pop the stack when done
        scope (exit)
            ns_stack = ns_stack[0 .. $ - 1];

        // fill the namespace with content from the analyse
        v.accept(this);
    }
}

private struct TransformToClassDiagram(ControllerT, LookupT) {
@safe:
    import cpptooling.analyzer.clang.analyze_helper : CXXMethodResult,
        ConstructorResult, DestructorResult, FieldDeclResult,
        CXXBaseSpecifierResult;
    import cpptooling.data.type : CppAccess;
    import cpptooling.data.type : CppNs;

    invariant {
        assert(uml !is null);
    }

    private {
        UMLClassDiagram uml;
        ControllerT ctrl;
        LookupT lookup;
    }

    /// If class methods should be part of the generated class diagrams.
    Flag!"genClassMethod" genClassMethod;

    /// If the parameters of methods should result in directed association.
    Flag!"genClassParamDependency" genClassParamDependency;

    /// If the inheritance hierarchy between classes is generated.
    Flag!"genClassInheritDependency" genClassInheritDependency;

    /// If the class members result in dependency on those members.
    Flag!"genClassMemberDependency" genClassMemberDependency;

    private static string toPrefix(CppAccess accessType) {
        import std.typecons : TypedefType;
        import cpptooling.data.type : CppAccess, AccessType;

        final switch (cast(TypedefType!CppAccess) accessType) {
        case AccessType.Public:
            return "+";
        case AccessType.Protected:
            return "#";
        case AccessType.Private:
            return "-";
        }
    }

    void put(ref const(TypeKindAttr) src, ref const(CXXBaseSpecifierResult) result) {
        import std.algorithm : map, joiner;
        import std.conv : text;
        import std.range : chain, only, retro;
        import cpptooling.analyzer.kind : TypeKind, TypeAttr;
        import cpptooling.analyzer.type : toStringDecl;

        if (genClassInheritDependency) {
            auto src_key = makeClassKey(src.kind.usr);

            auto canonical = lookup(result.canonicalUSR).front;
            auto dest_key = makeClassKey(canonical.usr);
            auto fqn = canonical.toStringDecl(TypeAttr.init);

            uml.relate(src_key, dest_key,
                    cast(UMLClassDiagram.DisplayName) fqn, Relate.Kind.Extend);
        }
    }

    /// Reconstruct the function signature as a UML comment.
    void put(ref const(TypeKindAttr) src, ref const(CXXMethodResult) result, in CppAccess accessType) {
        import std.algorithm : filter;
        import std.traits : ReturnType;
        import std.range : chain, only;
        import std.typecons : TypedefType;

        import cpptooling.data.type : CppConstMethod;
        import cpptooling.data.representation : CppMethod;

        ReturnType!makeClassKey src_key;

        if (genClassMethod || genClassParamDependency) {
            src_key = makeClassKey(src.kind.usr);
        }

        if (genClassMethod) {
            auto method = CppMethod(result.name, result.params, result.returnType,
                    accessType, CppConstMethod(result.isConst), result.virtualKind);
            uml.put(src_key, toPrefix(accessType) ~ method.toString);
        }

        if (genClassParamDependency) {
            // dfmt off
            auto relations =
                chain(getClassMethodRelation(result.params, lookup),
                      only(getTypeRelation(cast(TypedefType!CxReturnType) result.returnType, lookup)))
                .filter!(a => a.kind != Relate.Kind.None)
                // remove self referencing keys, would result in circles which
                // just clutters the diagrams
                .filter!(a => a.key != src.kind.usr);
            // dfmt on
            foreach (rel; relations) {
                auto dest_key = makeClassKey(rel.key);
                uml.relate(src_key, dest_key, rel.display, rel.kind);
            }
        }
    }

    void put(ref const(TypeKindAttr) src, ref const(ConstructorResult) result,
            in CppAccess accessType) {
        import std.algorithm : filter;
        import std.traits : ReturnType;
        import cpptooling.data.representation : CppCtor;

        ReturnType!makeClassKey src_key;

        if (genClassMethod || genClassParamDependency) {
            src_key = makeClassKey(src.kind.usr);
        }

        if (genClassMethod) {
            auto tor = CppCtor(result.name, result.params, accessType);
            uml.put(src_key, toPrefix(accessType) ~ tor.toString);
        }

        if (genClassParamDependency) {
            // dfmt off
            auto relations = getClassMethodRelation(result.params, lookup)
                .filter!(a => a.kind != Relate.Kind.None)
                // remove self referencing keys, would result in circles which
                // just clutters the diagrams
                .filter!(a => a.key != src.kind.usr);
            // dfmt on
            foreach (rel; relations) {
                auto dest_key = makeClassKey(rel.key);
                uml.relate(src_key, dest_key, rel.display, rel.kind);
            }
        }
    }

    void put(ref const(TypeKindAttr) src, ref const(DestructorResult) result, in CppAccess accessType) {
        import cpptooling.data.representation : CppDtor;

        if (genClassMethod) {
            auto key = makeClassKey(src.kind.usr);
            auto tor = CppDtor(result.name, accessType, result.virtualKind);
            uml.put(key, toPrefix(accessType) ~ tor.toString);
        }
    }

    void put(ref const(TypeKindAttr) src, ref const(FieldDeclResult) result, in CppAccess accessType) {
        import std.algorithm : filter;

        if (genClassMemberDependency) {
            auto rel = getClassMemberRelation(result.type, lookup);
            if (rel.kind != Relate.Kind.None) {
                auto src_key = makeClassKey(src.kind.usr);
                auto dest_key = makeClassKey(rel.key);
                uml.relate(src_key, dest_key, rel.display, rel.kind);
            }
        }
    }

    void put(ref const(ClassClassificationResult) result) {
        auto key = makeClassKey(result.type.kind.usr);
        uml.put(key, result.classification);
    }

    void put(ref const(ClassDeclResult) src, const(CppNs)[] reside_in) {
        import std.algorithm : map, joiner;
        import std.conv : text;
        import std.range : chain, only;

        auto key = makeClassKey(src.type.kind.usr);
        string fqn = chain(reside_in.map!(a => cast(string) a), only(cast(string) src.name)).joiner("::")
            .text;
        uml.put(key, cast(UMLClassDiagram.DisplayName) fqn);

        logger.tracef("foo: %s %s", key, fqn);
    }
}

private struct TransformToComponentDiagram(ControllerT, LookupT) {
    import std.algorithm : map, copy, each, joiner;
    import std.range : chain;
    import std.typecons : TypedefType;

    import cpptooling.analyzer.clang.analyze_helper : CXXBaseSpecifierResult,
        CXXMethodResult, ConstructorResult, DestructorResult, ClassDeclResult,
        FieldDeclResult, VarDeclResult, FunctionDeclResult;
    import cpptooling.data.symbol.container : Container;
    import cpptooling.data.type : CppAccess, CxReturnType;

    invariant {
        assert(diagram !is null);
        assert(ctrl !is null);
    }

    UMLComponentDiagram diagram;
    ControllerT ctrl;
    LookupT lookup;

    void put(ref const(TypeKindAttr) src, ref const(CXXBaseSpecifierResult) result) {
        auto r0 = lookup(result.canonicalUSR).map!(a => PathKind(a.loc.file,
                Relate.Kind.Associate));
        putDest(r0, src);
    }

    void put(ref const(TypeKindAttr) src, ref const(ConstructorResult) result,
            in CppAccess accessType) {
        auto dests = result.params.map!(a => paramToPathKind(a, lookup)).joiner;
        putDest(dests, src);
    }

    void put(ref const(TypeKindAttr) src, ref const(CXXMethodResult) result, in CppAccess accessType) {
        auto r0 = result.params.map!(a => paramToPathKind(a, lookup)).joiner;
        auto r1 = componentLookupType((cast(TypedefType!CxReturnType) result.returnType), lookup);
        auto dests = chain(r0, r1).map!(a => PathKind(a.file, Relate.Kind.Associate));
        putDest(dests, src);
    }

    void put(ref const(TypeKindAttr) src, ref const(FieldDeclResult) result, in CppAccess accessType) {
        // primitive types do not have a location
        if (result.type.kind.loc.kind == LocationTag.Kind.loc) {
            auto r = componentLookupType(result.type, lookup).map!(a => PathKind(a.file,
                    Relate.Kind.Associate));
            putDest(r, src);
        }
    }

    void put(ref const(TypeKindAttr) src, ref const(ClassClassificationResult) result) {
        putDest(result.type, src);
    }

    void put(ref const(VarDeclResult) result) {
        if (result.location.kind == LocationTag.Kind.loc) {
            putSrc(result.location);

            // dfmt off
            auto r = componentLookupType(result.type, lookup)
                .map!(a => PathKind(a.file, Relate.Kind.Associate));
            // dfmt on
            putDest(r, result.location);
        }
    }

    void put(ref const(FunctionDeclResult) result) {
        if (result.location.kind == LocationTag.Kind.loc) {
            auto r0 = result.params.map!(a => paramToPathKind(a, lookup)).joiner();
            auto r1 = componentLookupType((cast(TypedefType!CxReturnType) result.returnType),
                    lookup);
            auto dests = chain(r0, r1).map!(a => PathKind(a.file, Relate.Kind.Associate));
            putSrc(result.type);
            putDest(dests, result.type);
        }
    }

    void putSrc(ref const(TypeKindAttr) src) @safe {
        string location = src.kind.loc.file;

        if (!ctrl.doFile(location, location)) {
            return;
        }

        auto key = makeComponentKey(location, ctrl);
        diagram.put(key.key, cast(UMLComponentDiagram.DisplayName) key.display);
        diagram.put(key.key, cast(UMLComponentDiagram.Location) location);
    }

    void putSrc(ref const(LocationTag) src) @safe {
        string location = src.file;

        if (src.kind == LocationTag.Kind.noloc || !ctrl.doFile(location, location)) {
            return;
        }

        auto key = makeComponentKey(location, ctrl);
        diagram.put(key.key, cast(UMLComponentDiagram.DisplayName) key.display);
        diagram.put(key.key, cast(UMLComponentDiagram.Location) location);
    }

    void putDest(ref const(TypeKindAttr) dest, ref const(TypeKindAttr) src) @safe {
        import std.range : only;

        if (dest.kind.loc.kind == LocationTag.Kind.noloc) {
            return;
        }

        auto dests = only(PathKind(cast(string) dest.kind.loc.file, Relate.Kind.Associate));
        putDest(dests, src);
    }

    /** Create relations from src to those destinations in dests.
     * Params:
     *   dests = of PathKind, it is the destinations.
     *   src = the source that all the relations originate from.
     */
    void putDest(Range, SrcT)(ref Range dests, ref const(SrcT) src) @safe 
            if (is(ElementType!Range == PathKind)) {
        import std.algorithm : map, filter, cache;

        static if (is(SrcT == TypeKindAttr)) {
            auto source_key = makeComponentKey(src.kind.loc.file, ctrl);
        } else static if (is(SrcT == LocationTag)) {
            auto source_key = makeComponentKey(src.file, ctrl);
        } else {
            static assert("Type not supported (SrcT): " ~ SrcT.stringof);
        }

        // dfmt off
        foreach (a; dests
                 // ask pred if to keep the element
                 .filter!(a => ctrl.doFile(cast(string) a.file, cast(string) a.file))
                 .map!(a => KeyRelate(a.file, makeComponentKey(a.file, ctrl), a.kind))
                 .cache
                 // self referencing components are invalid
                 .filter!(a => a.key != source_key)) {
            diagram.relate(source_key.key, a.key.key, cast(UMLComponentDiagram.DisplayName) a.key.display, a.kind);
        }
        // dfmt on
    }
}

/** Route information to specific transformers.
 *
 * No manipulation of data is to be done in this struct. Only routing to
 * appropriate functions.
 */
struct TransformToDiagram(ControllerT, ParametersT) {
    import std.range : only;

    import cpptooling.analyzer.clang.analyze_helper : CXXBaseSpecifierResult,
        ClassDeclResult, FieldDeclResult, CXXMethodResult, ConstructorResult,
        DestructorResult, VarDeclResult, FunctionDeclResult;
    import cpptooling.analyzer.kind : TypeKind;
    import cpptooling.data.symbol.types : USRType;
    import cpptooling.data.type : CppNs, CppAccess;

    alias LookupType = typeof(Container.find!TypeKind(USRType())) delegate(USRType usr) @safe;

    private {
        TransformToComponentDiagram!(ControllerT, LookupType) toComponent;
        TransformToClassDiagram!(ControllerT, LookupType) toClass;
    }

    this(ControllerT ctrl, ParametersT params, LookupType lookup,
            UMLComponentDiagram comp_dia, UMLClassDiagram class_dia) {
        toComponent = typeof(toComponent)(comp_dia, ctrl, lookup);
        toClass = typeof(toClass)(class_dia, ctrl, lookup, params.genClassMethod,
                params.genClassParamDependency, params.genClassInheritDependency,
                params.genClassMemberDependency);
    }

@safe:

    /// A class.
    void put(ref const(ClassDeclResult) src, const(CppNs)[] reside_in) {
        toClass.put(src, reside_in);
        toComponent.putSrc(src.type);
    }

    void put(ref const(TypeKindAttr) src, ref const(CXXBaseSpecifierResult) result) {
        toClass.put(src, result);
        toComponent.put(src, result);
    }

    void put(ref const(TypeKindAttr) src, ref const(CXXMethodResult) result, in CppAccess accessType) {
        toClass.put(src, result, accessType);
        toComponent.put(src, result, accessType);
    }

    void put(ref const(TypeKindAttr) src, ref const(ConstructorResult) result,
            in CppAccess accessType) {
        toClass.put(src, result, accessType);
        toComponent.put(src, result, accessType);
    }

    void put(ref const(TypeKindAttr) src, ref const(DestructorResult) result, in CppAccess accessType) {
        toClass.put(src, result, accessType);
    }

    void put(ref const(TypeKindAttr) src, ref const(FieldDeclResult) result, in CppAccess accessType) {
        toClass.put(src, result, accessType);
        toComponent.put(src, result, accessType);
    }

    void put(ref const(ClassClassificationResult) result) {
        toClass.put(result);
    }

    /** A nested class.
     *
     * Propagate the classification and relation of the root->nested.
     */
    void put(ref const(TypeKindAttr) src, ref const(ClassClassificationResult) result) {
        toComponent.put(src, result);
        // only needs result
        toClass.put(result);
    }

    void put(ref const(VarDeclResult) result) {
        toComponent.put(result);
    }

    void put(ref const(FunctionDeclResult) result) {
        toComponent.put(result);
    }
}

// visualize where the module private starts
private: // ******************************************************************

import cpptooling.data.representation : CppRoot, CppClass, CppMethod, CppCtor,
    CppDtor, CppNamespace, CFunction, CxGlobalVariable;
import cpptooling.data.type : LocationTag, Location;
import cpptooling.data.symbol.container : Container;
import cpptooling.utility.conv : str;
import dsrcgen.plantuml;

alias KeyValue = Tuple!(UMLComponentDiagram.Key, "key", string, "display", string, "absFilePath");
alias KeyRelate = Tuple!(string, "file", KeyValue, "key", Relate.Kind, "kind");

/**
 * Params:
 *  file = filename of the relation.
 *  kind = kind of relation such as associaiton, composition etc.
 */
alias PathKind = Tuple!(string, "file", Relate.Kind, "kind");

/** Calculate the key based on the directory the file that declares the symbol exist in.
 *
 * Additional metadata as to make it possible to backtrack.
 */
KeyValue makeComponentKey(in string location_file, Controller ctrl) @trusted {
    import std.base64;
    import std.path;
    import std.array : appender;
    import std.typecons : tuple;

    //TODO consider using a hash function to shorten the length of the encoded path

    alias SafeBase64 = Base64Impl!('-', '_', Base64.NoPadding);

    string file_path = buildNormalizedPath(location_file.absolutePath);
    string strip_path = cast(string) ctrl.doComponentNameStrip(FileName(file_path));
    string rel_path = relativePath(strip_path);
    string display_name = strip_path.baseName;

    auto enc = appender!(char[])();
    SafeBase64.encode(cast(ubyte[]) rel_path, enc);

    auto k = KeyValue(UMLComponentDiagram.Key(enc.data.idup), display_name, strip_path);

    debug {
        logger.tracef("Component:%s stripped:%s file:%s base64:%s", k.display,
                strip_path, file_path, cast(string) k.key);
    }

    return k;
}

UMLClassDiagram.Key makeClassKey(in USRType key) @trusted {
    import std.base64;
    import std.array : appender;

    //TODO consider using a hash function to shorten the length of the encoded path

    alias SafeBase64 = Base64Impl!('-', '_', Base64.NoPadding);

    auto enc = appender!(char[])();
    SafeBase64.encode(cast(ubyte[])(cast(string) key), enc);

    auto k = UMLClassDiagram.Key(enc.data.idup);
    return k;
}

auto componentLookupType(LookupT)(TypeKindAttr type, LookupT lookup) @safe {
    import std.algorithm : map, filter, joiner;
    import std.range : only, dropOne;
    import cpptooling.analyzer.type : TypeKind;

    enum rel_kind = Relate.Kind.Associate;

    auto type_lookup = only(USRType.init).dropOne;
    auto rval = only(PathKind()).dropOne;

    if (type.attr.isPrimitive || type.kind.loc.kind == LocationTag.Kind.noloc) {
        return rval;
    }

    // because of the noloc check it is safe to assume that all locs are
    // now of type loc

    final switch (type.kind.info.kind) with (TypeKind.Info) {
    case Kind.record:
        rval = only(PathKind(type.kind.loc.file, rel_kind));
        break;
    case Kind.array:
        if (!type.kind.info.elementAttr.isPrimitive) {
            type_lookup = only(type.kind.info.element);
        }
        break;
    case Kind.simple:
        rval = only(PathKind(type.kind.loc.file, rel_kind));
        break;
    case Kind.func:
        rval = only(PathKind(type.kind.loc.file, rel_kind));
        break;
    case Kind.funcPtr:
        type_lookup = only(type.kind.info.pointee);
        break;
    case Kind.pointer:
        type_lookup = only(type.kind.info.pointee);
        break;
    case Kind.typeRef:
        rval = only(PathKind(type.kind.loc.file, rel_kind));
        break;
    case Kind.ctor:
    case Kind.dtor:
    case Kind.null_:
        break;
    }

    // dfmt off
    foreach (c; type_lookup
             .map!(a => lookup(a))
             .joiner()
             .filter!(a => a.loc.kind != LocationTag.Kind.noloc)) {
        rval = only(PathKind(c.loc.file, rel_kind));
    }
    // dfmt on

    return rval;
}

alias ClassRelate = Tuple!(Relate.Kind, "kind", Relate.Key, "key",
        UMLClassDiagram.DisplayName, "display");

auto getClassMemberRelation(LookupT)(TypeKindAttr type, LookupT lookup) {
    //TODO code duplication with getMethodRelation
    // .. fix it. This function is ugly.
    import std.algorithm : each, map, filter, joiner;
    import std.array : array;
    import std.typecons : tuple;
    import cpptooling.analyzer.type;

    auto r = ClassRelate(Relate.Kind.None, Relate.Key(""), UMLClassDiagram.DisplayName(""));

    final switch (type.kind.info.kind) with (TypeKind.Info) {
    case Kind.typeRef:
        auto tref = lookup(type.kind.info.canonicalRef);
        foreach (t; tref.filter!(a => a.info.kind == Kind.record)) {
            auto rel_type = Relate.Kind.Aggregate;
            if (type.attr.isPtr || type.attr.isRef) {
                rel_type = Relate.Kind.Compose;
            }
            r = ClassRelate(rel_type, t.usr,
                    cast(UMLClassDiagram.DisplayName) type.kind.toStringDecl(TypeAttr.init));
        }
        break;
    case Kind.record:
        r = ClassRelate(Relate.Kind.Aggregate, type.kind.usr,
                cast(UMLClassDiagram.DisplayName) type.kind.toStringDecl(TypeAttr.init));
        break;
    case Kind.array:
        auto element = lookup(type.kind.info.element);
        foreach (e; element.filter!(a => a.info.kind == Kind.record)) {
            auto rel_type = Relate.Kind.Aggregate;
            if (type.kind.info.elementAttr.isPtr || type.kind.info.elementAttr.isRef) {
                rel_type = Relate.Kind.Compose;
            }
            r = ClassRelate(rel_type, e.usr,
                    cast(UMLClassDiagram.DisplayName) type.kind.toStringDecl(TypeAttr.init));
        }
        break;
    case Kind.pointer:
        auto pointee = lookup(type.kind.info.pointee);
        foreach (p; pointee.filter!(a => a.info.kind == Kind.record)) {
            string display = p.toStringDecl(TypeAttr.init);
            r = ClassRelate(Relate.Kind.Compose, p.usr, cast(UMLClassDiagram.DisplayName) display);
        }
        break;
    case Kind.simple:
    case Kind.func:
    case Kind.funcPtr:
    case Kind.ctor:
    case Kind.dtor:
    case Kind.null_:
        break;
    }

    return r;
}

private ClassRelate getTypeRelation(LookupT)(TypeKindAttr tk, LookupT lookup) {
    import std.algorithm : filter;
    import cpptooling.analyzer.kind : TypeKind, TypeAttr;
    import cpptooling.analyzer.type : toStringDecl;

    auto r = ClassRelate(Relate.Kind.None, Relate.Key(""), UMLClassDiagram.DisplayName(""));

    final switch (tk.kind.info.kind) with (TypeKind.Info) {
    case Kind.typeRef:
        auto tref = lookup(tk.kind.info.canonicalRef);
        foreach (t; tref.filter!(a => a.info.kind == Kind.record)) {
            r = ClassRelate(Relate.Kind.Associate, Relate.Key(t.usr),
                    cast(UMLClassDiagram.DisplayName) t.toStringDecl(TypeAttr.init));
        }
        break;
    case Kind.record:
        r = ClassRelate(Relate.Kind.Associate, tk.kind.usr,
                cast(UMLClassDiagram.DisplayName) tk.kind.toStringDecl(TypeAttr.init));
        break;
    case Kind.array:
        auto element = lookup(tk.kind.info.element);
        foreach (e; element.filter!(a => a.info.kind == Kind.record)) {
            r = ClassRelate(Relate.Kind.Associate, e.usr,
                    cast(UMLClassDiagram.DisplayName) e.toStringDecl(TypeAttr.init));
        }
        break;
    case Kind.pointer:
        auto pointee = lookup(tk.kind.info.pointee);
        foreach (p; pointee.filter!(a => a.info.kind == Kind.record)) {
            string display = p.toStringDecl(TypeAttr.init);
            r = ClassRelate(Relate.Kind.Associate, Relate.Key(p.usr),
                    cast(UMLClassDiagram.DisplayName) display);
        }
        break;
    case Kind.simple:
    case Kind.func:
    case Kind.funcPtr:
    case Kind.ctor:
    case Kind.dtor:
    case Kind.null_:
    }

    return r;
}

private auto getClassMethodRelation(LookupT)(const(CxParam)[] params, LookupT lookup) {
    import std.array : array;
    import std.algorithm : among, map, filter;
    import std.variant : visit;
    import cpptooling.analyzer.kind : TypeKind, TypeAttr;
    import cpptooling.analyzer.type : TypeKindAttr, toStringDecl;
    import cpptooling.data.type : VariadicType;

    static ClassRelate genParam(CxParam p, LookupT lookup) @trusted {
        // dfmt off
        return p.visit!(
            (TypeKindVariable tkv) => getTypeRelation(tkv.type, lookup),
            (TypeKindAttr tk) => getTypeRelation(tk, lookup),
            (VariadicType vk)
                {
                    logger.error("Variadic function not supported.");
                    // Because what types is either discovered first at runtime
                    // or would require deeper inspection of the implementation
                    // where the variadic is used.
                    return ClassRelate.init;
                }
            );
        // dfmt on
    }

    // dfmt off
    return params.map!(a => genParam(a, lookup)).array();
    // dfmt on
}

private auto paramToPathKind(LookupT)(CxParam p, LookupT lookup) @trusted {
    import std.range : only, dropOne;
    import std.variant : visit;
    import cpptooling.data.representation : TypeKindVariable, VariadicType;

    // dfmt off
    return p.visit!(
                    (TypeKindVariable v) => componentLookupType(v.type, lookup),
                    (TypeKindAttr v) => componentLookupType(v, lookup),
                    (VariadicType v) {
                    logger.error(
                                 "Variadic function not supported. Would require runtime information to relate.");
                    return only(PathKind()).dropOne;
                    });
    // dfmt on
}

void generate(UMLClassDiagram uml_class, UMLComponentDiagram uml_comp,
        Flag!"doGenDot" doGenDot, Generator.Modules modules) @safe {
    import std.algorithm : each;
    import std.format : format;
    import std.range : enumerate;

    // TODO code duplicaton with class and component.
    // Generalize, reduce.

    auto classes_preamble = modules.classes.base;
    classes_preamble.suppressIndent(1);
    foreach (idx, kv; uml_class.fanOutSorted.enumerate) {
        generate(kv[0], kv[1], classes_preamble);
        generateClassRelate(uml_class.relateTo(kv[0])
                .toFlatArray(cast(Relate.Key) kv[0]), modules.classes);
        if (doGenDot) {
            auto nodes = modules.classes_dot.base;
            nodes.suppressIndent(1);
            nodes.stmt(format(`"%s" [label="%s"]`, kv[0].str, kv[1].displayName.str));

            // make a range of all relations from THIS to other components
            auto r = uml_class.relateTo(kv[0]).toRange(cast(Relate.Key) kv[0]);

            generateDotRelate(r, idx, modules.classes_dot);
        }
    }

    foreach (idx, kv; uml_comp.fanOutSorted.enumerate) {
        generate(kv[0], kv[1], modules.components);
        if (doGenDot) {
            auto nodes = modules.components_dot.base;
            nodes.suppressIndent(1);
            nodes.stmt(format(`"%s" [label="%s"]`, kv[0].str, kv[1].displayName.str));

            // make a range of all relations from THIS to other components
            auto r = uml_comp.relateTo(kv[0]).toRange(cast(Relate.Key) kv[0]);

            generateDotRelate(r, idx, modules.components_dot);
        }
    }
    generateComponentRelate(uml_comp.relateToFlatArray, modules.components);
}

/** Generate PlantUML class and relations from the class.
 *
 * By generating the relations out of the class directly after the class
 * definitions it makes it easier for GraphViz to generate a not-so-muddy
 * image.
 */
private void generate(UMLClassDiagram.Key key, const UMLClassDiagram.Class c, PlantumlModule m) @safe {
    import std.algorithm : each;
    import dsrcgen.plantuml : addSpot;

    ClassType pc;

    if (c.content.length == 0) {
        pc = m.class_(cast(string) c.displayName);
    } else {
        pc = m.classBody(cast(string) c.displayName);
        c.content.each!(a => pc.method(a));
    }
    pc.addAs.text(cast(string) key);

    //TODO add a plantuml macro and use that as color for interface
    // Allows the user to control the color via the PREFIX_style.iuml
    switch (c.classification) with (cpptooling.data.class_classification.State) {
    case Abstract:
        pc.addSpot("<< (A, Pink) >>");
        break;
    case VirtualDtor:
    case Pure:
        pc.addSpot("<< (I, LightBlue) >>");
        break;
    default:
        break;
    }
}

private void generateClassRelate(T)(T relate_range, PlantumlModule m) @safe {
    static auto convKind(Relate.Kind kind) {
        static import dsrcgen.plantuml;

        final switch (kind) with (Relate.Kind) {
        case None:
            assert(0);
        case Extend:
            return dsrcgen.plantuml.Relate.Extend;
        case Compose:
            return dsrcgen.plantuml.Relate.Compose;
        case Aggregate:
            return dsrcgen.plantuml.Relate.Aggregate;
        case Associate:
            return dsrcgen.plantuml.Relate.ArrowTo;
        case Relate:
            return dsrcgen.plantuml.Relate.Relate;
        }
    }

    foreach (r; relate_range) {
        m.relate(cast(ClassNameType) r.from, cast(ClassNameType) r.to, convKind(r.kind));
    }
}

private void generateDotRelate(T)(T relate_range, ulong color_idx, PlantumlModule m) @safe {
    import std.format : format;

    static import dsrcgen.plantuml;

    static string getColor(ulong idx) {
        static string[] colors = [
            "red", "mediumpurple", "darkorange", "deeppink", "green", "coral", "orangered", "plum", "deepskyblue",
            "slategray", "cadetblue", "olive", "silver", "indianred", "black"
        ];
        return colors[idx % colors.length];
    }

    if (relate_range.length > 0) {
        m.stmt(format("edge [color=%s]", getColor(color_idx)));
    }

    foreach (r; relate_range) {
        auto l = m.relate(cast(ClassNameType) r.from, cast(ClassNameType) r.to,
                dsrcgen.plantuml.Relate.DotArrowTo);
        //TODO this is ugly, fix dsrcgen relate to support graphviz/DOT
        auto w = new dsrcgen.plantuml.Text!PlantumlModule(format("[weight=%d] ", r.count));
        l.block.prepend(w);
    }
}

private void generate(UMLComponentDiagram.Key key,
        const UMLComponentDiagram.Component component, PlantumlModule m) @safe {
    import std.algorithm : map;
    import std.conv : text;
    import std.path : buildNormalizedPath, relativePath;

    auto comp = m.classBody(cast(string) component.displayName);
    comp.addAs.text(cast(string) key);

    // dfmt off
    foreach (fname; component.contains[]
        .map!(a => cast(string) a)
        .map!(a => () @trusted { return buildNormalizedPath(a).relativePath; }())) {
        comp.m.stmt(text(fname));
    }
    // dfmt on
}

private void generateComponentRelate(T)(T relate_range, PlantumlModule m) @safe {
    static auto convKind(Relate.Kind kind) {
        static import dsrcgen.plantuml;

        final switch (kind) with (Relate.Kind) {
        case Relate:
            return dsrcgen.plantuml.Relate.Relate;
        case Extend:
            assert(0);
        case Compose:
            assert(0);
        case Aggregate:
            assert(0);
        case Associate:
            return dsrcgen.plantuml.Relate.ArrowTo;
        case None:
            assert(0);
        }
    }

    foreach (r; relate_range) {
        m.relate(cast(ComponentNameType) r.from, cast(ComponentNameType) r.to, convKind(r.kind));
    }
}
