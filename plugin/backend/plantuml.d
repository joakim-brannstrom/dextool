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

import std.typecons : Typedef, Tuple, Flag, Yes, No;
import logger = std.experimental.logger;

import dsrcgen.plantuml;

import application.types;
import cpptooling.data.symbol.types : FullyQualifiedNameType;

version (unittest) {
    import test.helpers : shouldEqualPretty;
    import unit_threaded : Name, shouldEqual;
} else {
    struct Name {
        string name_;
    }
}

/** Control various aspectes of the analyze and generation like what nodes to
 * process.
 */
@safe interface Controller {
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
@safe pure const interface Parameters {
    import std.typecons : Tuple, Flag;

    alias Files = Tuple!(FileName, "classes", FileName, "components", FileName,
            "styleIncl", FileName, "styleOutput");

    /// Output directory to store files in.
    DirName getOutputDirectory();

    /// Files to write generated diagram data to.
    Files getFiles();

    /// Name affecting filenames.
    FilePrefix getFilePrefix();

    /// If class methods should be part of the generated class diagrams.
    Flag!"genClassMethod" genClassMethod();

    /// If the parameters of methods should result in directed association.
    Flag!"genClassParamDependency" genClassParamDependency();

    /// If the inheritance hierarchy between classes is generated.
    Flag!"genClassInheritDependency" genClassInheritDependency();

    /// If the class members result in dependency on those members.
    Flag!"genClassMemberDependency" genClassMemberDependency();

    /** In all diagrams generate an "!include" of the style file.
     *
     * If the file PREFIX_style do not exist, create it with a minimal style.
     * Currently just the direction but may change in the future.
     */
    Flag!"doStyleIncl" doStyleIncl();

    /// Generate a dot graph in the plantuml file
    Flag!"doGenDot" doGenDot();
}

/// Data produced by the generator like files.
@safe interface Products {
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
}

/** Relations to targets with count and kind.
 *
 * Intented to be used in a hashmap with the key as the "from".
 */
@safe struct Relate {
    alias Key = Typedef!(string, string.init, "RelateKey");

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

size_t[] nameIndexSortedRange(T, alias sortNameBy)(T arr) pure {
    import std.algorithm : makeIndex;

    auto index = new size_t[arr.length];

    makeIndex!((a, b) => sortNameBy(a) < sortNameBy(b))(arr, index);
    return index;
}

auto nameSortedRange(T, alias sortNameBy)(const T t) pure {
    import std.algorithm : map;
    import std.array : array;

    auto arr = t.asArray();
    auto index = nameIndexSortedRange!(typeof(arr), sortNameBy)(arr);

    return index.map!(i => arr[i]).array();
}

auto fanOutSorted(T)(T t) pure {
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
@safe class UMLClassDiagram {
    import cpptooling.data.representation : ClassVirtualType;

    alias Key = Typedef!(string, string.init, "UMLKey");

    struct Class {
        ClassVirtualType classification;
        string[] content;
    }

    /// The class is only added if it doesn't already exist in the store.
    void put(Key key) {
        if (key !in classes) {
            classes[key] = Class.init;
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

    void put(Key key, ClassVirtualType classification)
    in {
        assert(key in classes);
    }
    body {
        classes[key].classification = classification;
    }

    /** Add a relation between two classes and increase the count on the class
     * related TO.
     */
    void relate(Key from, Key to, Relate.Kind kind)
    out {
        assert(from in classes);
        assert(to in classes);
        assert(kind != Relate.Kind.None);
    }
    body {
        put(to);
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
        // dfmt off
    }

    auto nameSortedRange() const pure @trusted {
        static string sortClassNameBy(T)(ref T a) {
            return a[0].str;
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
        return classes.byKeyValue.map!(a => chain(only(format("%s%s", a.key.str, a.value.content.length == 0 ? "" : " {")),
                                                  a.value.content.dup.map!(b => "  " ~ b),
                                                  a.value.content.takeOne.map!(b => "} // " ~ a.key.str))
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
@safe class UMLComponentDiagram {
    alias Key = Typedef!(string, string.init, "UMLKey");

    struct Component {
        string displayName;
        string[] toFile;
    }

    /// The component is only added if it doesn't already exist in the store.
    void put(Key key, string displayName) {
        if (key !in components) {
            components[key] = Component(displayName);
            relate_to[cast(Relate.Key) key] = Relate.init;
        }
    }

    /** Add a relation between two components and increase the count on the class
     * related TO.
     */
    void relate(Key from, Key to, string toDisplayName, Relate.Kind kind)
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

    const(Relate) relateTo(Key k) pure const
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
        // dfmt off
    }

    auto nameSortedRange() const pure @trusted {
        static string sortComponentNameBy(T)(ref T a) {
            return a[1].displayName;
        }

        return .nameSortedRange!(typeof(this), sortComponentNameBy)(this);
    }

    private string[] componentsToStringArray() const pure @trusted {
        import std.algorithm : map;
        import std.array : array;
        import std.format : format;

        return nameSortedRange.map!(a => format("%s as %s", a[0].str, a[1].displayName)).array();
    }

    private string[] relateToStringArray() const pure @trusted {
        import std.algorithm : map, joiner;
        import std.array : array;

        return relate_to.byKeyValue.map!(a => a.value.toStringArray(a.key)).joiner().array();
    }

    override string toString() @safe pure const {
        import std.ascii : newline;
        import std.algorithm : joiner;
        import std.conv : text;
        import std.format : format;
        import std.range : only, chain;

        // dfmt off
        return chain(only(format("UML Component Diagram (Total %d) {", components.length)),
                     componentsToStringArray,
                     relateToStringArray,
                     only("} // UML Component Diagram"),
                     ).joiner(newline).text;
        // dfmt on
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
    uml.put(UMLClassDiagram.Key("A"));

    uml.toString.shouldEqualPretty("UML Class Diagram (Total 1) {
A
} // UML Class Diagram");
}

@Name("Should add a CppClass to the UML diagram, with methods")
unittest {
    import cpptooling.data.representation;

    auto uml = new UMLClassDiagram;
    auto c = CppClass(CppClassName("A"));
    {
        auto m = CppMethod(CppMethodName("fun"), CxReturnType(TypeKind.make("int")),
                CppAccess(AccessType.Public), CppConstMethod(false),
                CppVirtualMethod(MemberVirtualType.Virtual));
        c.put(m);
    }

    put(uml, c, Yes.genClassMethod, Yes.genClassParamDependency,
            Yes.genClassInheritDependency, Yes.genClassMemberDependency);

    uml.toString.shouldEqualPretty("UML Class Diagram (Total 1) {
A {
  +virtual int fun()
} // A
} // UML Class Diagram");
}

@Name("Should be a UML diagram with two classes related")
unittest {
    auto uml = new UMLClassDiagram;
    auto ka = UMLClassDiagram.Key("A");
    auto kb = UMLClassDiagram.Key("B");
    uml.put(ka);
    uml.put(kb);

    uml.relate(ka, kb, Relate.Kind.Extend);

    uml.toString.shouldEqualPretty("UML Class Diagram (Total 2) {
A
B
A -Extend- [1]B
} // UML Class Diagram");
}

@Name("Should be a UML Component diagram with two components related")
unittest {
    auto uml = new UMLComponentDiagram;
    auto ka = UMLComponentDiagram.Key("a");
    auto kb = UMLComponentDiagram.Key("b");
    uml.put(ka, "A");

    uml.relate(ka, kb, "B", Relate.Kind.Relate);

    uml.toString.shouldEqualPretty("UML Component Diagram (Total 2) {
a as A
b as B
a -Relate- [1]b
} // UML Component Diagram");
}

struct Generator {
    import cpptooling.data.representation : CppRoot;
    import cpptooling.data.symbol.container : Container;

    static struct Modules {
        PlantumlModule classes;
        PlantumlModule classes_dot;
        PlantumlModule components;
        PlantumlModule components_dot;

        static auto make() {
            Modules m;

            //TODO how to do this with meta-programming and introspection of Modules?
            m.classes = new PlantumlModule;
            m.classes_dot = new PlantumlModule;
            m.classes_dot.suppressIndent(1);
            m.components = new PlantumlModule;
            m.components_dot = new PlantumlModule;
            m.components_dot.suppressIndent(1);

            return m;
        }
    }

    this(Controller ctrl, Parameters params, Products products) {
        this.ctrl = ctrl;
        this.params = params;
        this.products = products;
        this.uml_class = new UMLClassDiagram;
        this.uml_component = new UMLComponentDiagram;
    }

    void analyze(ref CppRoot root, ref Container container) {
        import std.ascii;
        import cpptooling.data.representation : CppNamespace, CppNs;

        logger.trace("Raw:\n", root.toString());

        auto fl = rawFilter(root, ctrl, products);
        logger.trace("Filtered:\n", fl.toString());

        translate(fl, uml_class, params);
        translate(fl, uml_component, ctrl, params, container);
        logger.trace("Translated:\n", uml_class.toString, newline, uml_component.toString);
    }

    auto process() {
        auto m = Modules.make();
        generate(uml_class, uml_component, params.doGenDot, m);
        postProcess(ctrl, params, products, m);
    }

private:
    Controller ctrl;
    Parameters params;
    Products products;
    UMLClassDiagram uml_class;
    UMLComponentDiagram uml_component;

    static void postProcess(Controller ctrl, Parameters params, Products prods, Modules m) {
        static PlantumlRootModule makeMinimalStyle(Flag!"genClassMethod" show_methods) {
            auto proot = PlantumlRootModule.make();

            auto m = proot.makeUml;
            m.suppressIndent(1);
            m.stmt("left to right direction");
            m.stmt("skinparam componentStyle uml2");
            m.stmt("set namespaceSeparator ::");
            if (!show_methods) {
                m.stmt("hide members");
            }

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

        static PlantumlModule makeStyleInclude(FileName style_file) {
            auto m = new PlantumlModule;
            m.stmt("!include " ~ cast(string) style_file);

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

        if (params.doStyleIncl) {
            style = makeStyleInclude(params.getFiles.styleIncl);
        }

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

        makeUml(prods, params.getFiles.classes, style, m.classes);
        makeUml(prods, params.getFiles.components, style, m.components);
    }
}

private:
@safe:

import cpptooling.data.representation : CppRoot, CppClass, CppMethod, CppCtor,
    CppDtor, CppNamespace, CxLocation, CFunction, CxGlobalVariable;
import cpptooling.data.symbol.container : Container;
import cpptooling.utility.conv : str;
import dsrcgen.plantuml;

/** Structurally filter the data to remove unwanted parts.
 *
 * TODO consider skipping the filtering stage. It seems unnecessary
 *
 * Params:
 *  ctrl: control what symbols are kept, thus processed further
 */
T rawFilter(T)(T input, Controller ctrl, Products prod)
        if (is(T == CppRoot) || is(T == CppNamespace)) {
    import std.algorithm : each, filter, map;

    static if (is(T == CppRoot)) {
        auto raw = CppRoot(input.location);
    } else {
        auto raw = CppNamespace.make(input.name);
    }

    // dfmt off
    input.namespaceRange
        .map!(a => rawFilter(a, ctrl, prod))
        .each!(a => raw.put(a));

    input.classRange
        // ask controller if the file should be processed
        .filter!(a => ctrl.doFile(a.location.file, cast(string) a.name ~ " " ~ a.location.toString))
        .each!(a => raw.put(a));

    input.funcRange()
        .each!(a => raw.put(a));

    input.globalRange()
        .each!(a => raw.put(a));
    // dfmt on

    return raw;
}

bool isPrimitiveType(FullyQualifiedNameType type) {
    import std.algorithm : among;

    //TODO really ugly, consider some other way of doing this.
    // Copied from translateCursorType.
    // This is hard to keep in sync and error prone.

    return 0 != type.among("void", "bool", "unsigned char", "unsigned short", "unsigned int", "unsigned long",
            "unsigned long long", "char", "wchar", "short", "int", "long",
            "long long", "float", "double", "long double", "null");
}

void put(UMLClassDiagram uml, CppClass c, Flag!"genClassMethod" class_method,
        Flag!"genClassParamDependency" class_param_dep,
        Flag!"genClassInheritDependency" class_inherit_dep,
        Flag!"genClassMemberDependency" class_member_dep) {
    import std.algorithm : each, map, filter, joiner;
    import std.array : array;
    import cpptooling.data.representation;

    static string getMethod(T)(T method_, string prefix) @trusted {
        import std.variant : visit;

        return method_.visit!((CppMethod m) => prefix ~ m.toString,
                (CppMethodOp m) => prefix ~ m.toString,
                (CppCtor m) => prefix ~ m.toString, (CppDtor m) => prefix ~ m.toString);
    }

    static auto getMemberRelation(TypeKindVariable tkv) {
        import std.typecons : tuple;

        //TODO investigate why strip is needed when analyzing gtest
        import std.string : strip;

        final switch (tkv.type.info.kind) with (TypeKind.Info) {
        case Kind.record:
            return tuple(Relate.Key(tkv.type.info.type.strip), Relate.Kind.Aggregate);
        case Kind.simple:
            if (tkv.type.isRecord && (tkv.type.isPtr || tkv.type.isRef)) {
                return tuple(Relate.Key(tkv.type.info.type.strip), Relate.Kind.Compose);
            }
            return tuple(Relate.Key(""), Relate.Kind.None);
        case TypeKind.Info.Kind.func:
            goto case;
        case Kind.array:
            goto case;
        case Kind.funcPtr:
            goto case;
        case Kind.null_:
            return tuple(Relate.Key(""), Relate.Kind.None);
        }
    }

    static auto getMethodRelation(ref CppClass.CppFunc f) {
        import std.array : array;
        import std.algorithm : among, map;
        import std.variant : visit;
        import std.range : chain, only;
        import std.typecons : TypedefType, Tuple;

        alias Rtuple = Tuple!(Relate.Kind, "kind", Relate.Key, "key");

        static Rtuple getTypeRelation(TypeKind tk) {
            //TODO investigate why strip is needed when analyzing gtest
            import std.string : strip;

            auto r = Rtuple(Relate.Kind.None, Relate.Key(""));

            final switch (tk.info.kind) with (TypeKind.Info) {
            case Kind.record:
                r[0] = Relate.Kind.Associate;
                r[1] = tk.info.type.strip;
                break;
            case Kind.simple:
                if (tk.isRecord && (tk.isPtr || tk.isRef)) {
                    r[0] = Relate.Kind.Associate;
                    r[1] = tk.info.type.strip;
                }
                break;
            case TypeKind.Info.Kind.func:
                break;
            case Kind.array:
                r[0] = Relate.Kind.Associate;
                r[1] = tk.info.elementType.strip;
                break;
            case Kind.funcPtr:
                break;
            case Kind.null_:
                break;
            }

            if ((cast(FullyQualifiedNameType) r.key).isPrimitiveType) {
                r[0] = Relate.Kind.None;
            }

            return r;
        }

        static Rtuple genParam(CxParam p) @trusted {
            return p.visit!((TypeKindVariable tkv) => getTypeRelation(tkv.type),
                    (TypeKind tk) => getTypeRelation(tk), (VariadicType vk) {
                        logger.error(
                            "Variadic function not supported. Would require runtime information to relate.");
                        return Rtuple.init;
                    });
        }

        static Rtuple[] genMethod(T)(T f) {
            return chain(f.paramRange.map!(a => genParam(a)),
                    only(getTypeRelation(cast(TypedefType!CxReturnType) f.returnType))).array();
        }

        static Rtuple[] genCtor(CppCtor f) {
            return f.paramRange.map!(a => genParam(a)).array();
        }

        static Rtuple[] internalVisit(ref CppClass.CppFunc f) @trusted {
            return f.visit!((CppMethod m) => genMethod(m),
                    (CppMethodOp m) => genMethod(m), (CppCtor m) => genCtor(m),
                    (CppDtor m) => [Rtuple.init]);
        }

        return internalVisit(f);
    }

    auto key = UMLClassDiagram.Key(cast(string) c.fullyQualifiedName);

    uml.put(key);
    uml.put(key, c.classification);

    // dfmt off
    if (class_method) {
        c.methodPublicRange.map!(a => getMethod(a, "+")).each!(a => uml.put(key, a));
    }

    if (class_inherit_dep) {
        c.inheritRange
            .map!(a => Relate.Key(a.fullyQualifiedName.str))
            .each!(a => uml.relate(key, cast(UMLClassDiagram.Key) a, Relate.Kind.Extend));
    }

    if (class_member_dep) {
        c.memberRange
            .map!(a => getMemberRelation(a))
            .filter!(a => a[1] != Relate.Kind.None)
            .each!(a => uml.relate(key, cast(UMLClassDiagram.Key) a[0], a[1]));
    }

    if (class_param_dep) {
        foreach (a; c.methodRange
                 .map!(a => getMethodRelation(a))
                 // flatten the range
                 .joiner()
                 .filter!(a => a.kind != Relate.Kind.None)
                 // remove self referencing keys, would result in circles which
                 // just clutters the diagrams
                 .filter!(a => a.key != key)) {
            uml.relate(key, cast(UMLClassDiagram.Key) a.key, a.kind);
        }
    }
    // dfmt on
}

void put(T)(UMLComponentDiagram uml, T input, Controller ctrl, ref Container container)
        if (is(T == CppClass) || is(T == CFunction) || is(T == CxGlobalVariable)) {
    import std.algorithm : map, filter, cache, joiner;
    import std.range : only, chain, array, dropOne;
    import cpptooling.data.representation;
    import cpptooling.data.symbol.types;

    alias KeyValue = Tuple!(UMLComponentDiagram.Key, "key", string, "display",
            string, "absFilePath");
    alias KeyRelate = Tuple!(string, "file", KeyValue, "key", Relate.Kind, "kind");
    alias PathKind = Tuple!(string, "file", Relate.Kind, "kind");

    /** Calculate the key based on the directory the file that declares the symbol exist in.
     *
     * Additional metadata as to make it possible to backtrack.
     */
    static KeyValue makeKey(in string location_file, Controller ctrl) @trusted {
        import std.base64;
        import std.path;
        import std.array : appender;
        import std.typecons : tuple;

        //TODO consider using a hash function to shorten the length of the encoded path

        alias SafeBase64 = Base64Impl!('-', '_', Base64.NoPadding);

        string file_path = buildNormalizedPath(location_file).absolutePath;
        string strip_path = cast(string) ctrl.doComponentNameStrip(FileName(file_path.dirName));
        string rel_path = relativePath(strip_path);
        string display_name = strip_path.baseName;

        auto enc = appender!(char[])();
        SafeBase64.encode(cast(ubyte[]) rel_path, enc);

        auto k = KeyValue(UMLComponentDiagram.Key(enc.data.idup), display_name, strip_path);

        debug {
            logger.tracef("Component:%s stripped:%s file:%s base64:%s",
                    k.display, strip_path, file_path, cast(string) k.key);
        }

        return k;
    }

    static auto lookupType(TypeKind tk, ref Container container) {
        //TODO investigate why strip is needed when analyzing gtest
        import std.string : strip;

        auto type_lookup = only(FullyQualifiedNameType(string.init)).dropOne;
        auto rval = only(PathKind()).dropOne;

        final switch (tk.info.kind) with (TypeKind.Info) {
        case Kind.record:
            type_lookup = only(FullyQualifiedNameType(tk.info.type.strip));
            break;
        case Kind.simple:
            if (tk.isRecord && (tk.isPtr || tk.isRef)) {
                type_lookup = only(FullyQualifiedNameType(tk.info.type.strip));
            }
            break;
        case TypeKind.Info.Kind.func:
            break;
        case Kind.array:
            type_lookup = only(FullyQualifiedNameType(tk.info.elementType.strip));
            break;
        case Kind.funcPtr:
            break;
        case Kind.null_:
            break;
        }

        // dfmt off
        foreach (c; type_lookup
                 .filter!(a => !a.isPrimitiveType)
                 .map!(a => container.find!CppClass(a)).joiner()
                 ) {
            rval = only(PathKind(c.location.file, Relate.Kind.None));
        }
        // dfmt on

        return rval;
    }

    static auto getMemberRelation(TypeKindVariable tkv, ref Container container) {
        import std.typecons : tuple;

        return lookupType(tkv.type, container).map!(a => PathKind(a.file, Relate.Kind.Associate));
    }

    static auto getInheritRelation(CppInherit inherit, ref Container container) {
        auto rval = only(PathKind()).dropOne;

        foreach (c; container.find!CppClass(inherit.fullyQualifiedName)) {
            rval = only(PathKind(c.location.file, Relate.Kind.Associate));
        }

        return rval;
    }

    static auto genParam(CxParam p, ref Container container) @trusted {
        import std.variant : visit;

        // dfmt off
        return p.visit!(
                        (TypeKindVariable tkv) => lookupType(tkv.type, container),
                        (TypeKind tk) => lookupType(tk, container),
                        (VariadicType vk) {
                        logger.error(
                                     "Variadic function not supported. Would require runtime information to relate.");
                        return only(PathKind()).dropOne;
                        });
        // dfmt on
    }

    static PathKind[] getMethodRelation(ref CppClass.CppFunc f, ref Container container) {
        static auto genMethod(T)(T f, ref Container container) {
            import std.typecons : TypedefType;

            // dfmt off
            return chain(f.paramRange.map!(a => genParam(a, container)).joiner(),
                         lookupType(cast(TypedefType!CxReturnType) f.returnType, container));
            // dfmt on
        }

        static auto genCtor(CppCtor f, ref Container container) {
            return f.paramRange.map!(a => genParam(a, container)).joiner();
        }

        static PathKind[] internalVisit(ref CppClass.CppFunc f, ref Container container) @trusted {
            import std.variant : visit;

            // dfmt off
            return f.visit!((CppMethod m) => genMethod(m, container).array(),
                    (CppMethodOp m) => genMethod(m, container).array(),
                    (CppCtor m) => genCtor(m, container).array(),
                    (CppDtor m) => PathKind[].init);
            // dfmt on
        }

        auto rval = PathKind[].init;

        return internalVisit(f, container).map!(a => PathKind(a.file,
                Relate.Kind.Associate)).array();
    }

    static auto getFreeFuncRelation(ref CFunction f, ref Container container) {
        import std.typecons : TypedefType;

        // dfmt off
        return chain(f.paramRange.map!(a => genParam(a, container)).joiner(),
                     lookupType(cast(TypedefType!CxReturnType) f.returnType, container))
            .map!(a => PathKind(a.file, Relate.Kind.Associate));
        // dfmt on
    }

    auto key = makeKey(input.location.file, ctrl);
    uml.put(key.key, key.display);

    // dfmt off
    static if (is(T == CppClass)) {
        auto path_kind_range =
            chain(input.memberRange.map!(a => getMemberRelation(a, container)).joiner(),
                  input.inheritRange.map!(a => getInheritRelation(a, container)).joiner(),
                  input.methodRange.map!(a => getMethodRelation(a, container)).joiner(),
                 );
    } else static if (is(T == CFunction)) {
        auto path_kind_range = getFreeFuncRelation(input, container);
    } else static if (is(T == CxGlobalVariable)) {
        auto path_kind_range =
            lookupType(input.type, container)
            .map!(a => PathKind(a.file, Relate.Kind.Associate));
    }

    foreach (a; path_kind_range
        // ask controller if the file should be processed
        .filter!(a => ctrl.doFile(a.file, cast(string) a.file))
        .map!(a => KeyRelate(a.file, makeKey(a.file, ctrl), a.kind))
        .cache
        // self referencing components are invalid
        .filter!(a => a.key != key)) {
        uml.relate(key.key, a.key.key, a.key.display, a.kind);
    }
    // dfmt on
}

void translate(T)(T input, UMLClassDiagram uml_class, Parameters params)
        if (is(T == CppRoot) || is(T == CppNamespace)) {
    foreach (ref c; input.classRange) {
        put(uml_class, c, params.genClassMethod, params.genClassParamDependency,
                params.genClassInheritDependency, params.genClassMemberDependency);
    }

    foreach (ref ns; input.namespaceRange) {
        translate(ns, uml_class, params);
    }
}

void translate(T)(T input, UMLComponentDiagram uml_comp, Controller ctrl,
        Parameters params, ref Container container)
        if (is(T == CppRoot) || is(T == CppNamespace) || is(T == CxGlobalVariable)) {
    void putRange(T)(T r) {
        foreach (ref c; r) {
            put(uml_comp, c, ctrl, container);
        }
    }

    putRange(input.classRange);
    putRange(input.funcRange);
    putRange(input.globalRange);

    foreach (ref ns; input.namespaceRange) {
        translate(ns, uml_comp, ctrl, params, container);
    }
}

void generate(UMLClassDiagram uml_class, UMLComponentDiagram uml_comp,
        Flag!"doGenDot" doGenDot, Generator.Modules modules) {
    import std.algorithm : each;
    import std.format : format;
    import std.range : enumerate;

    foreach (idx, kv; uml_class.fanOutSorted.enumerate) {
        generate(kv[0], kv[1], uml_class.relateTo(kv[0]), modules.classes);
        if (doGenDot) {
            generateDotRelate(uml_class.relateTo(kv[0])
                    .toRange(cast(Relate.Key) kv[0]), idx, modules.classes_dot);
        }
    }

    auto nodes = modules.components_dot.base;
    nodes.suppressIndent(1);

    foreach (idx, kv; uml_comp.fanOutSorted.enumerate) {
        generate(kv[0], kv[1], modules.components);
        if (doGenDot) {
            nodes.stmt(format(`"%s" [label="%s"]`, cast(string) kv[0], kv[1].displayName));
            auto rels = modules.components_dot.base;
            rels.suppressIndent(1);
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
void generate(UMLClassDiagram.Key name, const(UMLClassDiagram.Class) c,
        const Relate rels, PlantumlModule m) {
    import std.algorithm : each;

    ClassType pc;

    if (c.content.length == 0) {
        pc = m.class_(cast(string) name);
    } else {
        pc = m.classBody(cast(string) name);
        c.content.each!(a => pc.method(a));
    }

    import cpptooling.data.representation : ClassVirtualType;
    import dsrcgen.plantuml : addSpot;

    //TODO add a plantuml macro and use that as color for interface
    // Allows the user to control the color via the PREFIX_style.iuml
    switch (c.classification) with (ClassVirtualType) {
    case Abstract:
        pc.addSpot.text("(A, Pink)");
        break;
    case VirtualDtor:
        goto case;
    case Pure:
        pc.addSpot.text("(I, LightBlue)");
        break;
    default:
        break;
    }

    generateClassRelate(rels.toFlatArray(cast(Relate.Key) name), m);
}

void generateClassRelate(T)(T relate_range, PlantumlModule m) {
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

void generateDotRelate(T)(T relate_range, ulong color_idx, PlantumlModule m) {
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

void generate(UMLComponentDiagram.Key key,
        const UMLComponentDiagram.Component component, PlantumlModule m) {
    auto comp = m.component(component.displayName);
    comp.addAs.text(cast(string) key);
}

void generateComponentRelate(T)(T relate_range, PlantumlModule m) {
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
