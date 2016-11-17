/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Overall design of the data flow when analyzing.
 - Visitor pull data from the AST.
 - Visitor push data to the general Transform.
 - The Transform splice the data and forwards to the specialized transformers.
   The top Transform act as a mediator. It do not have any logic or knowledge
   other than how to forward the data to the specialized transforms.
 - The specialized transformers finalizes the data, delays, decisions etc.
   They decide when to do the final forwarding to the diagrams.
 - The UML diagrams are processed by the Generator.
   The generator transforms the in-memory representation to content suitable to
   store in files.
 - The generator forwards the content to a receiver, the registered Products.
 - Backend done. See frontend for what happens with the Products.
*/
module plugin.backend.plantuml;

import std.meta : templateAnd, templateOr;
import std.range : ElementType;
import std.typecons : Flag, Yes, No;
import logger = std.experimental.logger;

import dsrcgen.plantuml;

import application.types;
import cpptooling.analyzer.kind : TypeKind, TypeAttr, resolveCanonicalType;
import cpptooling.analyzer.type : USRType, TypeKindAttr;
import cpptooling.analyzer.clang.ast : Visitor;
import cpptooling.data.type : CxParam, CxReturnType, TypeKindVariable;
import cpptooling.data.symbol.types : FullyQualifiedNameType;
import cpptooling.analyzer.clang.analyze_helper : ClassStructDeclResult;
import plugin.utility : MarkArray;

static import cpptooling.data.class_classification;

version (unittest) {
    import test.extra_should : shouldEqualPretty;
    import unit_threaded : Name, shouldEqual;
} else {
    private struct Name {
        string name_;
    }
}

/** Control various aspects of the analyze and generation like what nodes to
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
    import std.typecons : Flag;

    static struct Files {
        FileName classes;
        FileName components;
        FileName styleIncl;
        FileName styleOutput;
    }

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

    /// Dummy to make the interface structurally compatible with cppvariant.Products
    void putLocation(FileName loc, LocationType type);
}

/** The supported "kind"s of relations between entities. Related to the UML
 * standard.
 */
enum RelateKind {
    None,
    Extend,
    Compose,
    Aggregate,
    Associate,
    Relate
}

/** Relations to targets with count and kind.
 *
 * Intented to be used in a hashmap with the key as the "from".
 */
private struct Relate {
@safe:
    alias Key = USRType;
    alias Kind = RelateKind;

    private static struct Inner {
        uint count;
        Kind kind;
    }

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

        static struct RelateTuple {
            Relate.Key from;
            Relate.Key to;
            ulong count;
        }

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

        static struct RelateTuple {
            Relate.Key from;
            Kind kind;
            Relate.Key to;
            ulong count;
        }

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

    // dfmt off
    makeIndex!((a, b) => t.relate_to[cast(Relate.Key) a.key].fanOut > t.relate_to[cast(Relate.Key) b.key].fanOut)(arr, fanout_i);
    // dfmt on

    return fanout_i.map!(i => arr[i]).array();
}

/** UML Class Diagram.
 *
 * Not designed for the general case.
 * The design is what the plantuml plugin needs when analyzing more than one
 * file. This is the container that is then passed between the analyze stages.
 *
 * All classes must exist in "classes".
 * It is common that during data gathering a class is found to be related to
 * another class by a USR. The relation is added before the class represented
 * by the USR is added.
 *
 * A --> B
 * Directed relation.
 * A can have many connections to B.
 *
 * Store of R[A.B].
 * When analyzing the structural data it is this kind of relations that are
 * found. From a class to many X, where X is other classes.
 * The key used must be unique, thus the choice of using USR.
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
 * The relations are of the kind Fan-out, one-to-many.
 * They can be sorted in descending fan-out-count order.
 */
class UMLClassDiagram {
@safe:
    import std.typecons : NullableRef;
    import std.format : FormatSpec;

    alias ClassClassificationState = cpptooling.data.class_classification.State;

    alias Key = USRType;
    struct DisplayName {
        string payload;
        alias payload this;
    }

    struct Content {
        string payload;
        alias payload this;
    }

    private struct Class {
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

    /** Store parameter content with the key.
     *
     * It is the body of the class in a class diagram.
     */
    void put(Key key, Content content)
    in {
        assert(key in classes);
    }
    body {
        classes[key].content ~= cast(string) content;
    }

    /** Set the classification of a class.
     *
     * Example would be a pure virtual, which in java would be an interface.
     */
    void set(Key key, ClassClassificationState classification)
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

    /** Use to retrieve the relation struct for the key.
     *
     * Example:
     * ---
     * diagram.relateTo(Key("foo")).put(Key("bar"), Relate.Kind.Associate);
     * ---
     */
    const(Relate) relateTo(Key k) pure const
    in {
        assert(k in classes);
        assert((cast(Relate.Key) k) in relate_to);
    }
    body {
        return relate_to[cast(Relate.Key) k];
    }

    /// Returns: Flat array of all relations of type FROM-KIND-TO-COUNT.
    auto relateToFlatArray() pure const @trusted {
        import std.algorithm : map, joiner;
        import std.array : array;

        return relate_to.byKeyValue.map!(a => a.value.toFlatArray(a.key)).joiner().array();
    }

    private static struct KeyClass {
        Key key;
        const(Class) value;
    }

    /// Returns: An array of the key/values.
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

    /// Returns: An array of the key/values sorted on key.
    auto nameSortedRange() const pure @trusted {
        static string sortClassNameBy(T)(ref T a) {
            return a.value.displayName;
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
        return classes
            .byKeyValue
            .map!(a => chain(only(format("%s -> %s%s",
                                         a.value.displayName,
                                         a.key,
                                         a.value.content.length == 0 ? "" : " {")),
                             a.value.content.dup.map!(b => "  " ~ b),
                             a.value.content.takeOne.map!(b => "} // " ~ a.value.displayName))
                  .joiner(newline)
                  .text)
            .array();
        // dfmt on
    }

    private string[] relateToStringArray() const pure @trusted {
        import std.algorithm : map, joiner;
        import std.array : array;

        return relate_to.byKeyValue.map!(a => a.value.toStringArray(a.key)).joiner().array();
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char) const {
        import std.ascii : newline;
        import std.format : formattedWrite;
        import std.range.primitives : put;
        import std.range : zip, repeat;

        formattedWrite(w, "UML Class Diagram (Total %d) {", classes.length);
        put(w, newline);
        foreach (a; zip(classesToStringArray, repeat(newline))) {
            put(w, a[0]);
            put(w, a[1]);
        }
        foreach (a; zip(relateToStringArray, repeat(newline))) {
            put(w, a[0]);
            put(w, a[1]);
        }
        put(w, "} // UML Class Diagram");
    }

    override string toString() @safe pure const {
        import std.exception : assumeUnique;
        import std.format : FormatSpec;

        char[] buf;
        buf.reserve(100);
        auto fmt = FormatSpec!char("%s");
        toString((const(char)[] s) { buf ~= s; }, fmt);
        auto trustedUnique(T)(T t) @trusted {
            return assumeUnique(t);
        }

        return trustedUnique(buf);
    }

    private Relate[Relate.Key] relate_to;
    private Class[Key] classes;
}

/** UML Component Diagram.
 *
 * Not designed for the general case.
 * The design is what the plantuml plugin needs when analyzing more than one
 * file. This is the container that is then passed between the analyze stages.
 *
 * The relations are of the kind Fan-out.
 *
 * See_Also: UMLClassDiagram
 */
class UMLComponentDiagram {
    import std.container.rbtree : RedBlackTree;

    struct Key {
        string payload;
        alias payload this;
    }

    struct Location {
        string payload;
        alias payload this;
    }

    struct DisplayName {
        string payload;
        alias payload this;
    }

    private struct Component {
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

    /** Use to retrieve the relation struct for the key.
     *
     * Example:
     * ---
     * diagram.relateTo(Key("foo")).put(Key("bar"), Relate.Kind.Associate);
     * ---
     */
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

    private static struct KeyComponent {
        Key key;
        const(Component) value;
    }

    /// Returns: Flat array of all relations of type FROM-KIND-TO-COUNT.
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

    /// Returns: An array of the key/values sorted on key.
    auto nameSortedRange() const pure @trusted {
        static string sortComponentNameBy(T)(ref T a) {
            return cast(string) a.value.displayName;
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
            .map!(a => tuple(a.key, a.value.displayName, a.value.contains[].map!(a => newline ~ "  " ~ cast(string) a).joiner))
            .map!(a => format("%s as %s%s", a[0],
                a[1],
                a[2])).array();
        // dfmt on
    }

    private string[] relateToStringArray() const pure @trusted {
        import std.algorithm : map, joiner;
        import std.array : array;

        return relate_to.byKeyValue.map!(a => a.value.toStringArray(a.key)).joiner().array();
    }

    /// String representation of the Component Diagram.
    void toString(Writer)(scope Writer w) @safe const {
        import std.ascii : newline;
        import std.format : formattedWrite;
        import std.range.primitives : put;
        import std.range : zip, repeat;

        formattedWrite(w, "UML Component Diagram (Total %d) {", components.length);
        put(w, newline);
        foreach (a; zip(componentsToStringArray, repeat(newline))) {
            put(w, a[0]);
            put(w, a[1]);
        }
        foreach (a; zip(relateToStringArray, repeat(newline))) {
            put(w, a[0]);
            put(w, a[1]);
        }
        put(w, "} // UML Component Diagram");
    }

    ///
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

private:
    Relate[Relate.Key] relate_to;
    Component[Key] components;
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

/** Context for the UML diagram generator from internal representation to the
 * concrete files.
 */
struct Generator {
    import cpptooling.data.representation : CppRoot;
    import cpptooling.data.symbol.container : Container;

    private static struct Modules {
        private static void postInit(ref typeof(this) m) {
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

    /** Instansiate.
     *
     * Params:
     *  ctrl = dynamic control of data generation.
     *  params = static control, may never change during generation.
     *  products = receiver of UML diagrams.
     */
    this(Controller ctrl, Parameters params, Products products) {
        this.ctrl = ctrl;
        this.params = params;
        this.products = products;
        this.umlClass = new UMLClassDiagram;
        this.umlComponent = new UMLComponentDiagram;
    }

    /** Process the sources to produce UML diagrams in-memory.
     *
     * The diagrams are forwarded to the registered Products instance.
     */
    auto process() {
        auto m = Modules.make();
        generate(umlClass, umlComponent, params.doGenDot, m);
        postProcess(ctrl, params, products, m);
    }

    /// The UML diagram used as source during generation.
    UMLClassDiagram umlClass;

    /// ditto
    UMLComponentDiagram umlComponent;

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

            m.stmt("!include " ~ style_file ~ "!" ~ to!string(cast(int) style_type));

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

            auto fname_dot = FileName(fname.stripExtension ~ ext_dot);
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
            import std.path : extension, stripExtension;

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

private struct ClassClassificationResult {
    TypeKindAttr type;
    cpptooling.data.class_classification.State classification;
}

private final class UMLClassVisitor(ControllerT, ReceiveT) : Visitor {
    import std.algorithm : map, copy, each, joiner;
    import std.array : Appender;
    import std.typecons : scoped, NullableRef;

    import cpptooling.analyzer.clang.ast : ClassDecl, CXXBaseSpecifier,
        Constructor, Destructor, CXXMethod, FieldDecl, CXXAccessSpecifier,
        generateIndentIncrDecr;
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
        NullableRef!ReceiveT recv;

        Container* container;
        CppNsStack ns_stack;
        CppAccess access;

        /// If the class has any members.
        Flag!"hasMember" hasMember;
    }

    this(TypeKindAttr type, const(CppNs)[] reside_in_ns, ControllerT ctrl,
            ref ReceiveT recv, ref Container container, in uint indent) {
        this.ctrl = ctrl;
        this.recv = &recv;
        this.container = &container;
        this.indent = indent;
        this.ns_stack = CppNsStack(reside_in_ns.dup);

        this.access = CppAccess(AccessType.Private);
        this.classification = ClassificationState.Unknown;

        this.type = type;
    }

    /// Nested class definitions.
    override void visit(const(ClassDecl) v) @trusted {
        mixin(mixinNodeLog!());
        logger.info("class: ", v.cursor.spelling);

        auto result = analyzeClassDecl(v, *container, indent);

        foreach (loc; container.find!LocationTag(result.type.kind.usr).map!(a => a.any).joiner) {
            if (!ctrl.doFile(loc.file, loc.file)) {
                return;
            }
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

        debug {
            import std.algorithm : each;
            import std.range : retro;
            import cpptooling.data.representation : CppInherit;

            auto inherit = CppInherit(result.name, result.access);
            retro(result.reverseScope).each!(a => inherit.put(a));

            logger.trace("inherit: ", inherit.toString);
        }

        recv.put(this.type, result);
    }

    override void visit(const(Constructor) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeConstructor(v, *container, indent);

        debug {
            auto tor = CppCtor(result.type.kind.usr, result.name, result.params, access);
            logger.trace("ctor: ", tor.toString);
        }

        recv.put(this.type, result, access);
    }

    override void visit(const(Destructor) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeDestructor(v, *container, indent);
        classification = classifyClass(classification, MethodKind.Dtor,
                cast(MemberVirtualType) result.virtualKind, hasMember);

        debug {
            auto tor = CppDtor(result.type.kind.usr, result.name, access, result.virtualKind);
            logger.trace("dtor: ", tor.toString);
        }

        recv.put(this.type, result, access);
    }

    override void visit(const(CXXMethod) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeCXXMethod(v, *container, indent);

        classification = classifyClass(classification, MethodKind.Method,
                cast(MemberVirtualType) result.virtualKind, hasMember);

        debug {
            import cpptooling.data.type : CppConstMethod;
            import cpptooling.data.representation : CppMethod;

            auto method = CppMethod(result.type.kind.usr, result.name, result.params,
                    result.returnType, access, CppConstMethod(result.isConst), result.virtualKind);
            logger.trace("method: ", method.toString);
        }

        recv.put(this.type, result, access);
    }

    override void visit(const(FieldDecl) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeFieldDecl(v, *container, indent);

        // TODO probably not necessary for classification to store it as a
        // member. Instead extend MethodKind to having a "Member".
        hasMember = Yes.hasMember;
        classification = classifyClass(classification, MethodKind.Unknown,
                MemberVirtualType.Unknown, hasMember);
        debug {
            logger.trace("member: ", cast(string) result.name);
        }

        recv.put(this.type, result, access);
    }

    override void visit(const(CXXAccessSpecifier) v) @trusted {
        mixin(mixinNodeLog!());
        access = CppAccess(toAccessType(v.cursor.access.accessSpecifier));
    }
}

final class UMLVisitor(ControllerT, ReceiveT) : Visitor {
    import std.algorithm : map, filter, cache, joiner;
    import std.range : chain, only, dropOne, ElementType;
    import std.typecons : scoped, NullableRef;

    import cpptooling.analyzer.clang.ast : TranslationUnit, UnexposedDecl,
        VarDecl, FunctionDecl, ClassDecl, Namespace, generateIndentIncrDecr;
    import cpptooling.analyzer.clang.analyze_helper : analyzeFunctionDecl,
        analyzeVarDecl, analyzeClassDecl, analyzeTranslationUnit;
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

    this(ControllerT ctrl, ref ReceiveT recv, ref Container container) {
        this.ctrl = ctrl;
        this.recv = recv;
        this.container = &container;
    }

    override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());
        v.accept(this);

        auto result = analyzeTranslationUnit(v, container, indent);
        recv.put(result);
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

        debug {
            logger.info("global variable: ", cast(string) result.name);
        }

        recv.put(result);
    }

    override void visit(const(FunctionDecl) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeFunctionDecl(v, container, indent);

        debug {
            auto func = CFunction(result.type.kind.usr, result.name, result.params,
                    CxReturnType(result.returnType), result.isVariadic, result.storageClass);
            logger.info("function: ", func.toString);
        }

        recv.put(result);
    }

    override void visit(const(ClassDecl) v) @trusted {
        mixin(mixinNodeLog!());
        logger.info("class: ", v.cursor.spelling);

        auto result = analyzeClassDecl(v, container, indent);

        foreach (loc; container.find!LocationTag(result.type.kind.usr).map!(a => a.any).joiner) {
            if (!ctrl.doFile(loc.file, loc.file)) {
                return;
            }
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

    private static string toPrefix(CppAccess access) {
        import cpptooling.data.type : CppAccess, AccessType;

        final switch (access) {
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

            auto canonical = lookup.kind(result.canonicalUSR).front;
            auto dest_key = makeClassKey(canonical.usr);
            auto fqn = canonical.toStringDecl(TypeAttr.init);

            uml.relate(src_key, dest_key,
                    cast(UMLClassDiagram.DisplayName) fqn, Relate.Kind.Extend);
        }
    }

    /// Reconstruct the function signature as a UML comment.
    void put(ref const(TypeKindAttr) src, ref const(CXXMethodResult) result, in CppAccess access) {
        import std.algorithm : filter;
        import std.traits : ReturnType;
        import std.range : chain, only;

        import cpptooling.data.type : CppConstMethod;
        import cpptooling.data.representation : CppMethod;

        ReturnType!makeClassKey src_key;

        if (genClassMethod || genClassParamDependency) {
            src_key = makeClassKey(src.kind.usr);
        }

        if (genClassMethod) {
            auto method = CppMethod(USRType("dummy"), result.name, result.params,
                    result.returnType, access, CppConstMethod(result.isConst), result.virtualKind);
            method.usr.nullify;
            uml.put(src_key, UMLClassDiagram.Content(toPrefix(access) ~ method.toString));
        }

        if (genClassParamDependency) {
            // dfmt off
            auto relations =
                chain(getClassMethodRelation(result.params, lookup),
                      only(getTypeRelation(cast(TypeKindAttr) result.returnType, lookup)))
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

    void put(ref const(TypeKindAttr) src, ref const(ConstructorResult) result, in CppAccess access) {
        import std.algorithm : filter;
        import std.traits : ReturnType;
        import cpptooling.data.representation : CppCtor;

        ReturnType!makeClassKey src_key;

        if (genClassMethod || genClassParamDependency) {
            src_key = makeClassKey(src.kind.usr);
        }

        if (genClassMethod) {
            auto tor = CppCtor(result.type.kind.usr, result.name, result.params, access);
            uml.put(src_key, UMLClassDiagram.Content(toPrefix(access) ~ tor.toString));
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

    void put(ref const(TypeKindAttr) src, ref const(DestructorResult) result, in CppAccess access) {
        import cpptooling.data.representation : CppDtor;

        if (genClassMethod) {
            auto key = makeClassKey(src.kind.usr);
            auto tor = CppDtor(result.type.kind.usr, result.name, access, result.virtualKind);
            uml.put(key, UMLClassDiagram.Content(toPrefix(access) ~ tor.toString));
        }
    }

    void put(ref const(TypeKindAttr) src, ref const(FieldDeclResult) result, in CppAccess access) {
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
        uml.set(key, result.classification);
    }

    void put(ref const(ClassStructDeclResult) src, const(CppNs)[] reside_in) {
        import std.algorithm : map, joiner;
        import std.conv : text;
        import std.range : chain, only;

        auto key = makeClassKey(src.type.kind.usr);
        string fqn = chain(reside_in.map!(a => cast(string) a), only(cast(string) src.name)).joiner("::")
            .text;
        uml.put(key, cast(UMLClassDiagram.DisplayName) fqn);
    }
}

/** Transform data from a data source (via push) to a UML component diagram.
 *
 * The component diagram is built upon the assumption that the physical
 * location of a declaration/definition has a correlation to the design the
 * creator had in mind.
 *
 * Physical world -> mental model.
 *
 * Design of relations transform:
 * A relation is based on where the identifier is located to the owner of the
 * type.
 * Identifier-location -> Type-owner-location.
 *
 * A type-owner-location is where the type is defined.
 * This though creates a problem when considering forward declarations in
 * combination with pointers, references, parameters.
 *
 * To handle the above case relations are go through three steps.
 *  - Add relations with USR->USR.
 *  - First try. Check both USRs location. If both of them are definitions then
 *    accept the relation. Otherwise put it into the cache.
 *  - Second try. Process the cache at the end of a translation unit. Same
 *    criteria as the first try.
 *  - Third try. When all translation units have been processed use a fallback
 *    strategy for those items left in the cache. At this stage a location
 *    corresponding to a declaration is OK. Reason, better than nothing.
 *
 * In the following example the processing is a.h before b.h.
 * If the locatoin of the forward declaration of B had been used the relation
 * from a.h to b.h would have been lost.
 *
 * Example:
 * a.h
 * ---
 * class B;
 * class A {
 *  B* b;
 * };
 * ---
 *
 * b.h
 * ---
 * class B {};
 * ---
 */
private @safe struct TransformToComponentDiagram(ControllerT, LookupT) {
    import std.algorithm : map, copy, each, joiner;
    import std.range : chain;

    import cpptooling.analyzer.clang.analyze_helper : CXXBaseSpecifierResult,
        CXXMethodResult, ConstructorResult, DestructorResult,
        ClassStructDeclResult, FieldDeclResult, VarDeclResult,
        FunctionDeclResult, TranslationUnitResult;
    import cpptooling.data.symbol.container : Container;
    import cpptooling.data.type : CppAccess, CxReturnType;

    invariant {
        assert(diagram !is null);
        assert(ctrl !is null);
    }

    private {
        static struct USRRelation {
            USRType from;
            USRType to;
            Relate.Kind kind;
        }

        UMLComponentDiagram diagram;
        ControllerT ctrl;
        LookupT lookup;
        MarkArray!USRRelation dcache;
        USRType[] src_cache;
    }

    this(UMLComponentDiagram diagram, ControllerT ctrl, LookupT lookup) {
        this.diagram = diagram;
        this.ctrl = ctrl;
        this.lookup = lookup;
    }

    /** Store the relations in the cache for later resolution regarding there
     * location.
     *
     * The concept is a source has relations to many destinations.
     *
     * The relation is hard coded as an Association.
     * If the function is generalized to be reused with Class then the hard
     * coded must be a lookup table or something to allow differentiating
     * depending on "stuff".
     *
     * It is by design that the src do NOT go via resolveCanonicalType. A free
     * variable that is a pointer shall have the "src" still as the pointer
     * itself but the destination is the pointed at type.
     *
     * Params:
     *  src = source of the relations
     *  range = destinations of the relations
     *  target = cache to put the values into
     *  lookup = type supporting lookups via USR for the TypeKind
     */
    static void putToCache(Range, T)(USRType src, Range range, ref T target, LookupT lookup) @safe 
            if (is(ElementType!Range == TypeKindAttr)
                || is(ElementType!Range == const(TypeKindAttr))) {
        import std.algorithm : filter;

        // dfmt off
        foreach(a; range
            // remove primitive types
            .filter!(a => a.kind.info.kind != TypeKind.Info.Kind.primitive)
            .map!(a => resolveCanonicalType(a.kind, a.attr, lookup))
            .joiner
            .map!(a => a.kind.usr)
            // create the relations of type src-to-kind
            .map!(to_ => USRRelation(src, to_, Relate.Kind.Associate))) {
            target.put(a);
        }
        // dfmt on
    }

    /// ditto
    static void putParamsToCache(T)(ref const(TypeKindAttr) src,
            const(CxParam)[] params, ref T target, LookupT lookup) @safe {
        // dfmt off
        auto range = params
            // returns a bunch of ranges of the unpacked parameters
            .map!(a => unpackParam(a))
            .joiner;
        // dfmt on

        putToCache(src.kind.usr, range, target, lookup);
    }

    static void finalizeSrcCache(LookupT, TargetT)(USRType[] cache, LookupT lookup, TargetT target) {
        import std.algorithm : map, joiner;

        // dfmt off
        foreach (loc; cache
                 .map!(usr => lookup.location(usr))
                 .joiner
                 .map!(a => a.any)
                 .joiner) {
            target.putSrc(loc);
        }
        // dfmt on
    }

    /// Process the last bits left in the cache.
    void finalize() {
        import std.algorithm : map, filter, cache;
        import std.range : enumerate, only;
        import std.typecons : tuple;

        finalizeSrcCache(src_cache[], lookup, this);
        if (src_cache.length > 0) {
            logger.tracef("%d relations left in src cache", src_cache.length);
        }
        src_cache.length = 0;

        if (dcache.data.length > 0) {
            logger.tracef("%d relations left. Activating fallback strategy", dcache.data.length);
        }

        // dfmt off
        foreach (e; dcache.data
                 // keep track of the index to allow marking of the cache for removal
                 .enumerate
                 // find the types
                 .map!(a => tuple(a.index, lookup.location(a.value.from), lookup.location(a.value.to)))
                 .cache
                 // a zero range means a failed lookup, a broken relation
                 .filter!(a => a[1].length != 0 && a[2].length != 0)
                 // unpack with fallback
                 .map!(a => tuple(a[0], a[1].front.any, a[2].front.any))
                 // ensure that both both resulted in valid ranges
                 .filter!(a => a[1].length != 0 && a[2].length != 0)
                 // unpack
                 .map!(a => tuple(a[0], a[1].front, a[2].front))
                 // check via ctrl (the user) if the destination is "ok"
                 .filter!(a => ctrl.doFile(cast(string) a[2].file, cast(string) a[2].file))
                 ) {
            //TODO warn when a declaration has been used?

            putDest(e[1], e[2], Relate.Kind.Associate);
            dcache.markForRemoval(e[0]);
        }
        // dfmt on

        dcache.doRemoval;

        if (dcache.data.length > 0) {
            logger.errorf("Fallback strategy failed for %d USRs. They are:", dcache.data.length);
        }

        foreach (e; dcache.data) {
            logger.tracef("  %s -> %s", cast(string) e.from, cast(string) e.to);
        }
    }

    void put(ref const(TranslationUnitResult) result) {
        import std.algorithm : map, filter, cache;
        import std.range : enumerate, only;
        import std.typecons : tuple;

        finalizeSrcCache(src_cache[], lookup, this);
        if (src_cache.length > 0) {
            logger.tracef("%d relations left in src cache", src_cache.length);
        }
        src_cache.length = 0;

        // dfmt off
        foreach (e; dcache.data
                 // keep track of the index to allow marking of the cache for removal
                 .enumerate
                 // find the types
                 .map!(a => tuple(a.index, lookup.location(a.value.from), lookup.location(a.value.to)))
                 .cache
                 // a zero range means a failed lookup, a broken relation
                 .filter!(a => a[1].length != 0 && a[2].length != 0)
                 // unpack
                 .map!(a => tuple(a[0], a[1].front, a[2].front))
                 // only okey with a relatioin TO something that is a definition
                 .filter!(a => a[1].hasDefinition && a[2].hasDefinition)
                 // check via ctrl (the user) if the destination is "ok"
                 .filter!(a => ctrl.doFile(cast(string) a[2].definition.file, cast(string) a[2].definition.file))
                 ) {
            putDest(e[1].definition, e[2].definition, Relate.Kind.Associate);
            dcache.markForRemoval(e[0]);
        }
        // dfmt on

        dcache.doRemoval;
    }

    void put(ref const(ClassStructDeclResult) result) {
        src_cache ~= result.type.kind.usr;
    }

    void put(ref const(TypeKindAttr) src, ref const(ConstructorResult) result, in CppAccess access) {
        putParamsToCache(src, result.params, dcache, lookup);
    }

    void put(ref const(TypeKindAttr) src, ref const(CXXMethodResult) result, in CppAccess access) {
        import std.range : only;

        putParamsToCache(src, result.params, dcache, lookup);
        putToCache(src.kind.usr, only((cast(const TypeKindAttr) result.returnType)), dcache, lookup);
    }

    void put(ref const(TypeKindAttr) src, ref const(FieldDeclResult) result, in CppAccess access) {
        import std.range : only;

        putToCache(src.kind.usr, only(result.type), dcache, lookup);
    }

    void put(ref const(TypeKindAttr) src, ref const(ClassClassificationResult) result) {
        import std.range : only;

        // called when creating a relation for a nested class
        putToCache(src.kind.usr, only(result.type), dcache, lookup);
    }

    void put(ref const(TypeKindAttr) src, ref const(CXXBaseSpecifierResult) result) {
        auto r0 = lookup.kind(result.canonicalUSR).map!(a => TypeKindAttr(a.get, TypeAttr.init));

        putToCache(src.kind.usr, r0, dcache, lookup);
    }

    void put(ref const(VarDeclResult) result) {
        import std.range : only;

        // primitive types do not have a location
        if (result.location.kind == LocationTag.Kind.loc) {
            putSrc(result.location);

            putToCache(result.instanceUSR, only(result.type), dcache, lookup);
        }
    }

    void put(ref const(FunctionDeclResult) result) {
        import std.range : only;

        src_cache ~= result.type.kind.usr;

        putParamsToCache(result.type, result.params, dcache, lookup);
        putToCache(result.type.kind.usr,
                only(cast(const TypeKindAttr) result.returnType), dcache, lookup);
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

    void putDest(ref const(LocationTag) src, ref const(LocationTag) dest, Relate.Kind kind) {
        auto src_ = makeComponentKey(src.file, ctrl);
        auto dest_ = makeComponentKey(dest.file, ctrl);

        // Ignoring self referencing relations.
        if (src_.key == dest_.key) {
            return;
        }

        diagram.relate(src_.key, dest_.key,
                cast(UMLComponentDiagram.DisplayName) dest_.display, kind);
    }
}

/** Route information to specific transformers.
 *
 * No manipulation of data is to be done in this struct. Only routing to
 * appropriate functions.
 */
class TransformToDiagram(ControllerT, ParametersT, LookupT) {
    import std.range : only;

    import cpptooling.analyzer.clang.analyze_helper : CXXBaseSpecifierResult,
        ClassStructDeclResult, FieldDeclResult, CXXMethodResult,
        ConstructorResult, DestructorResult, VarDeclResult, FunctionDeclResult,
        TranslationUnitResult;
    import cpptooling.analyzer.kind : TypeKind;
    import cpptooling.data.symbol.types : USRType;
    import cpptooling.data.type : CppNs, CppAccess;

    private {
        TransformToComponentDiagram!(ControllerT, LookupT) to_component;
        TransformToClassDiagram!(ControllerT, LookupT) to_class;
    }

    this(ControllerT ctrl, ParametersT params, LookupT lookup,
            UMLComponentDiagram comp_dia, UMLClassDiagram class_dia) {
        to_component = typeof(to_component)(comp_dia, ctrl, lookup);
        to_class = typeof(to_class)(class_dia, ctrl, lookup, params.genClassMethod,
                params.genClassParamDependency, params.genClassInheritDependency,
                params.genClassMemberDependency);
    }

@safe:

    /** Signal that diagrams to perform a finalization of cached data.
     */
    void finalize() {
        to_component.finalize();
    }

    void put(ref const(TranslationUnitResult) result) {
        to_component.put(result);
    }

    void put(ref const(ClassStructDeclResult) result, const(CppNs)[] reside_in) {
        to_class.put(result, reside_in);
        to_component.put(result);
    }

    void put(ref const(TypeKindAttr) src, ref const(CXXBaseSpecifierResult) result) {
        to_class.put(src, result);
        to_component.put(src, result);
    }

    void put(ref const(TypeKindAttr) src, ref const(CXXMethodResult) result, in CppAccess access) {
        to_class.put(src, result, access);
        to_component.put(src, result, access);
    }

    void put(ref const(TypeKindAttr) src, ref const(ConstructorResult) result, in CppAccess access) {
        to_class.put(src, result, access);
        to_component.put(src, result, access);
    }

    void put(ref const(TypeKindAttr) src, ref const(DestructorResult) result, in CppAccess access) {
        to_class.put(src, result, access);
    }

    void put(ref const(TypeKindAttr) src, ref const(FieldDeclResult) result, in CppAccess access) {
        to_class.put(src, result, access);
        to_component.put(src, result, access);
    }

    void put(ref const(ClassClassificationResult) result) {
        to_class.put(result);
    }

    /** A nested class.
     *
     * Propagate the classification and relation of the root->nested.
     */
    void put(ref const(TypeKindAttr) src, ref const(ClassClassificationResult) result) {
        to_component.put(src, result);
        // only needs result
        to_class.put(result);
    }

    void put(ref const(VarDeclResult) result) {
        to_component.put(result);
    }

    void put(ref const(FunctionDeclResult) result) {
        to_component.put(result);
    }
}

// visualize where the module private starts
private: // ******************************************************************

import cpptooling.data.representation : CppRoot, CppClass, CppMethod, CppCtor,
    CppDtor, CppNamespace, CFunction, CxGlobalVariable;
import cpptooling.data.type : LocationTag, Location;
import cpptooling.data.symbol.container : Container;
import dsrcgen.plantuml;

struct KeyValue {
    UMLComponentDiagram.Key key;
    string display;
    string absFilePath;
}

struct KeyRelate {
    string file;
    KeyValue key;
    Relate.Kind kind;
}

/**
 * Params:
 *  file = filename of the relation.
 *  kind = kind of relation such as associaiton, composition etc.
 */
struct PathKind {
    string file;
    Relate.Kind kind;
}

/** Calculate the key based on the directory the file that declares the symbol exist in.
 *
 * Additional metadata as to make it possible to backtrack.
 */
KeyValue makeComponentKey(in string location_file, Controller ctrl) @trusted {
    import std.array : appender;
    import std.base64 : Base64Impl, Base64;
    import std.path : buildNormalizedPath, absolutePath, relativePath, baseName;
    import std.typecons : tuple;

    // TODO consider using hash murmur2/3 to shorten the length of the encoded
    // path

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
    import std.base64 : Base64Impl, Base64;
    import std.array : appender;

    // TODO consider using hash murmur2/3 function to shorten the length of the
    // encoded path

    alias SafeBase64 = Base64Impl!('-', '_', Base64.NoPadding);

    auto enc = appender!(char[])();
    SafeBase64.encode(cast(ubyte[])(cast(string) key), enc);

    auto k = UMLClassDiagram.Key(enc.data.idup);
    return k;
}

private auto unpackParam(CxParam p) @trusted {
    import std.range : only, dropOne;
    import std.variant : visit;
    import cpptooling.data.representation : TypeKindVariable, VariadicType;

    // dfmt off
    return p.visit!(
                    (TypeKindVariable v) => only(v.type),
                    (TypeKindAttr v) => only(v),
                    (VariadicType v) {
                        logger.error(
                                     "Variadic function not supported. Would require runtime information to relate.");
                        return only(TypeKindAttr.init).dropOne;
                    });
    // dfmt on
}

struct ClassRelate {
    Relate.Kind kind;
    Relate.Key key;
    UMLClassDiagram.DisplayName display;
}

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
        auto tref = lookup.kind(type.kind.info.canonicalRef);
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
        auto element = lookup.kind(type.kind.info.element);
        foreach (e; element.filter!(a => a.info.kind == Kind.record)) {
            auto rel_type = Relate.Kind.Aggregate;
            if (type.attr.isPtr || type.attr.isRef) {
                rel_type = Relate.Kind.Compose;
            }
            r = ClassRelate(rel_type, e.usr,
                    cast(UMLClassDiagram.DisplayName) type.kind.toStringDecl(TypeAttr.init));
        }
        break;
    case Kind.pointer:
        auto pointee = lookup.kind(type.kind.info.pointee);
        foreach (p; pointee.filter!(a => a.info.kind == Kind.record)) {
            string display = p.toStringDecl(TypeAttr.init);
            r = ClassRelate(Relate.Kind.Compose, p.usr, cast(UMLClassDiagram.DisplayName) display);
        }
        break;
    case Kind.primitive:
    case Kind.simple:
    case Kind.func:
    case Kind.funcPtr:
    case Kind.funcSignature:
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
        auto tref = lookup.kind(tk.kind.info.canonicalRef);
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
        auto element = lookup.kind(tk.kind.info.element);
        foreach (e; element.filter!(a => a.info.kind == Kind.record)) {
            r = ClassRelate(Relate.Kind.Associate, e.usr,
                    cast(UMLClassDiagram.DisplayName) e.toStringDecl(TypeAttr.init));
        }
        break;
    case Kind.pointer:
        auto pointee = lookup.kind(tk.kind.info.pointee);
        foreach (p; pointee.filter!(a => a.info.kind == Kind.record)) {
            string display = p.toStringDecl(TypeAttr.init);
            r = ClassRelate(Relate.Kind.Associate, Relate.Key(p.usr),
                    cast(UMLClassDiagram.DisplayName) display);
        }
        break;
    case Kind.primitive:
    case Kind.simple:
    case Kind.func:
    case Kind.funcPtr:
    case Kind.funcSignature:
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
        generate(kv.key, kv.value, classes_preamble);
        generateClassRelate(uml_class.relateTo(kv.key)
                .toFlatArray(cast(Relate.Key) kv.key), modules.classes);
        if (doGenDot) {
            auto nodes = modules.classes_dot.base;
            nodes.suppressIndent(1);
            nodes.stmt(format(`"%s" [label="%s"]`, kv.key, kv.value.displayName));

            // make a range of all relations from THIS to other components
            auto r = uml_class.relateTo(kv.key).toRange(cast(Relate.Key) kv.key);

            generateDotRelate(r, idx, modules.classes_dot);
        }
    }

    foreach (idx, kv; uml_comp.fanOutSorted.enumerate) {
        generate(kv.key, kv.value, modules.components);
        if (doGenDot) {
            auto nodes = modules.components_dot.base;
            nodes.suppressIndent(1);
            nodes.stmt(format(`"%s" [label="%s"]`, kv.key, kv.value.displayName));

            // make a range of all relations from THIS to other components
            auto r = uml_comp.relateTo(kv.key).toRange(cast(Relate.Key) kv.key);

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
