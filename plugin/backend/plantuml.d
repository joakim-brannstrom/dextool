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
}

/// Parameters used during generation.
/// Important aspact that they do NOT change, therefore it is pure.
@safe pure const interface Parameters {
    import std.typecons : Tuple, Flag;

    alias Files = Tuple!(FileName, "classes", FileName, "styleIncl", FileName, "styleOutput");

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

/** Collection of UML data.
 *
 * Not designed for the general case.
 * The design is what the plantuml plugin needs when analyzing more than one
 * file. This is the container that is then passed between the analyze stages.
 *
 * TODO cleanup documentation. It is the design background and thoughts.
 * May not reflect the final design.
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
 * found. From A CppClass to X, where X is other CppClass.
 * The key used must contain the full relation name A::B.
 *
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
 * Fan-out collection.
 */
@safe class UMLCollection {
    alias UMLKey = Typedef!(string, string.init, "UMLKey");
    alias ClassKey = Typedef!(string, string.init, "UMLKey");
    alias RelateKey = Typedef!(string, string.init, "UMLKey");

    struct Class {
        string[] content;
    }

    struct Relate {
        enum Kind {
            None,
            Extend,
            Compose,
            Aggregate,
            Associate
        }

        private alias Inner = Tuple!(uint, "count", Kind, "kind");
        private Inner[][RelateKey] to;

        void put(RelateKey to_, Kind kind) {
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

        /// Convert the TO/value store to a FROM-KIND-TO-COUNT array.
        auto toFlatArray(const RelateKey from) pure const @trusted {
            import std.algorithm : filter, map, joiner;
            import std.array : array;

            alias RelateTuple = Tuple!(RelateKey, "from", Kind, "kind",
                    RelateKey, "to", uint, "count");

            // dfmt off
            return to.byKeyValue.map!(a => a.value
                                        .filter!(b => b.kind != Kind.None)
                                        .map!(b => RelateTuple(from, b.kind, a.key, b.count))
                                        .array())
                .joiner()
                .array();
            // dfmt on
        }

        auto toStringArray(const RelateKey from) pure const @trusted {
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

    /// The class is only added if it doesn't already exist in the store.
    void put(ClassKey key) {
        if (key !in classes) {
            classes[key] = Class.init;
            relateTo[key] = Relate.init;
        }
    }

    void put(ClassKey key, string content)
    in {
        assert(key in classes);
    }
    body {
        classes[key].content ~= content;
    }

    /** Add a relation between two classes and increase the count on the class
     * related TO.
     */
    void relate(ClassKey from, ClassKey to, Relate.Kind kind)
    out {
        assert(from in classes);
        assert(to in classes);
        assert(kind != Relate.Kind.None);
    }
    body {
        put(to);
        relateTo[from].put(to, kind);
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

        return relateTo.byKeyValue.map!(a => a.value.toStringArray(a.key)).joiner().array();
    }

    /// Return: Flat array of all relations of type FROM-KIND-TO-COUNT.
    auto relateToFlatArray() pure const @trusted {
        import std.algorithm : map, joiner;
        import std.array;

        return relateTo.byKeyValue.map!(a => a.value.toFlatArray(a.key)).joiner().array();
    }

    auto sortedClassRange() pure @trusted {
        import std.array : array;
        import std.algorithm;
        import std.typecons : tuple;
        import std.algorithm : makeIndex, uniq, map;

        //TODO how to do this without so much generated GC

        // dfmt off
        auto arr = classes.byKeyValue
            .map!(a => tuple(a.key, a.value))
            .array();
        auto index = new size_t[arr.length];

        makeIndex!((a, b) => a[0].str < b[0].str)(arr, index);

        return index.map!(i => arr[i]).array();
        // dfmt on
    }

    override string toString() @safe pure const {
        import std.ascii : newline;
        import std.algorithm : joiner, filter;
        import std.conv : text;
        import std.format : format;
        import std.range : takeOne, only, chain;

        // dfmt off
        return chain(only(format("UML Class Diagram (Total %d) {",classes.length)),
                     classesToStringArray,
                     relateToStringArray,
                     only("} // UML Class Diagram"),
                     ).joiner(newline).text;
        // dfmt on
    }

private:
    Class[ClassKey] classes;
    Relate[RelateKey] relateTo;
}

@Name("Should be a None relate not shown and an extended relate")
unittest {
    UMLCollection.Relate r;
    r.put(UMLCollection.RelateKey("B"), UMLCollection.Relate.Kind.None);
    r.put(UMLCollection.RelateKey("B"), UMLCollection.Relate.Kind.Extend);

    r.toStringArray(UMLCollection.RelateKey("A")).shouldEqual(["A -Extend- [1]B"]);
}

@Name("Should be all types of relates")
unittest {
    UMLCollection.Relate r;
    r.put(UMLCollection.RelateKey("B"), UMLCollection.Relate.Kind.None);
    r.put(UMLCollection.RelateKey("B"), UMLCollection.Relate.Kind.Extend);
    r.put(UMLCollection.RelateKey("B"), UMLCollection.Relate.Kind.Compose);
    r.put(UMLCollection.RelateKey("B"), UMLCollection.Relate.Kind.Aggregate);
    r.put(UMLCollection.RelateKey("B"), UMLCollection.Relate.Kind.Associate);

    r.toStringArray(UMLCollection.RelateKey("A")).shouldEqual(["A -Extend- [1]B",
            "A -Compose- [1]B", "A -Aggregate- [1]B", "A -Associate- [1]B"]);
}

@Name("Should be two relates to the same target")
unittest {
    UMLCollection.Relate r;
    r.put(UMLCollection.RelateKey("B"), UMLCollection.Relate.Kind.Compose);
    r.put(UMLCollection.RelateKey("B"), UMLCollection.Relate.Kind.Compose);

    r.toStringArray(UMLCollection.RelateKey("A")).shouldEqual(["A -Compose- [2]B"]);
}

@Name("Should be a UML diagram with one class")
unittest {
    import unit_threaded : writelnUt;

    auto uml = new UMLCollection;
    uml.put(UMLCollection.ClassKey("A"));

    writelnUt(uml.toString);
    uml.toString.shouldEqualPretty("UML Class Diagram (Total 1) {
A
} // UML Class Diagram");
}

@Name("Should add a CppClass to the UML diagram, with methods")
unittest {
    import cpptooling.data.representation;

    auto uml = new UMLCollection;
    auto c = CppClass(CppClassName("A"));
    {
        auto m = CppMethod(CppMethodName("fun"), CxReturnType(TypeKind.make("int")),
                CppAccess(AccessType.Public), CppConstMethod(false),
                CppVirtualMethod(VirtualType.Yes));
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
    import unit_threaded : writelnUt;

    auto uml = new UMLCollection;
    auto ka = UMLCollection.ClassKey("A");
    auto kb = UMLCollection.ClassKey("B");
    uml.put(ka);
    uml.put(kb);

    uml.relate(ka, kb, UMLCollection.Relate.Kind.Extend);

    writelnUt(uml.toString);
    uml.toString.shouldEqualPretty("UML Class Diagram (Total 2) {
A
B
A -Extend- [1]B
} // UML Class Diagram");
}

struct Generator {
    import cpptooling.data.representation : CppRoot;
    import cpptooling.data.symbol.container : Container;

    static struct Modules {
        PlantumlModule classes;

        static auto make() {
            Modules m;

            //TODO how to do this with meta-programming and introspection of Modules?
            m.classes = new PlantumlModule;
            //TODO activate suppression. NOT done in this PR. Results in too
            // much noise.
            //m.classes.suppressIndent(1);

            return m;
        }
    }

    this(Controller ctrl, Parameters params, Products products) {
        this.ctrl = ctrl;
        this.params = params;
        this.products = products;
        this.uml = new UMLCollection;
    }

    void analyze(ref CppRoot root, ref Container container) {
        import cpptooling.data.representation : CppNamespace, CppNs;

        logger.trace("Raw:\n", root.toString());

        auto fl = rawFilter(root, ctrl, products);
        logger.trace("Filtered:\n", fl.toString());

        translate(fl, uml, params);
        logger.trace("Translated:\n", uml.toString);
    }

    auto process() {
        auto m = Modules.make();
        generate(uml, m);
        postProcess(ctrl, params, products, m);
    }

private:
    Controller ctrl;
    Parameters params;
    Products products;
    UMLCollection uml;

    static void postProcess(Controller ctrl, Parameters params, Products prods, Modules m) {
        static PlantumlRootModule makeMinimalStyle() {
            auto proot = PlantumlRootModule.make();

            auto m = new PlantumlModule;
            m.stmt("left to right direction");
            proot.content.append(m);

            return proot;
        }

        static PlantumlModule makeStyleInclude(FileName style_file) {
            auto m = new PlantumlModule;
            m.stmt("!include " ~ cast(string) style_file);

            return m;
        }

        static PlantumlRootModule output(PlantumlModule[] pm) {
            import std.algorithm : filter;

            auto proot = PlantumlRootModule.make();

            foreach (m; pm.filter!(a => a !is null)) {
                proot.content.append(m);
            }

            return proot;
        }

        PlantumlModule style;

        if (params.doStyleIncl) {
            style = makeStyleInclude(params.getFiles.styleIncl);
        }

        if (ctrl.genStyleInclFile) {
            prods.putFile(params.getFiles.styleOutput, makeMinimalStyle);
        }

        PlantumlModule[] class_module;
        class_module ~= style;
        class_module ~= m.classes;

        prods.putFile(params.getFiles.classes, output(class_module));
    }
}

private:
@safe:

import cpptooling.data.representation : CppRoot, CppClass, CppMethod, CppCtor,
    CppDtor, CFunction, CppNamespace, CxLocation;
import dsrcgen.plantuml;
import cpptooling.utility.conv : str;

/** Structurally filter the data to remove unwanted parts.
 *
 * Remove:
 *  - free functions.
 *  - global variables.
 *  - anonymouse namespaces.
 *
 * Params:
 *  ctrl: control what symbols are kept, thus processed further
 */
CppRoot rawFilter(CppRoot input, Controller ctrl, Products prod) {
    import std.algorithm : each, filter, map;
    import cpptooling.data.representation : VirtualType;

    auto raw = CppRoot(input.location);

    // dfmt off
    input.namespaceRange
        .filter!(a => !a.isAnonymous)
        .map!(a => rawFilter(a, ctrl, prod))
        .each!(a => raw.put(a));

    input.classRange
        // ask controller if the file should be processed
        .filter!(a => ctrl.doFile(a.location.file, cast(string) a.name ~ " " ~ a.location.toString))
        .each!(a => raw.put(a));
    // dfmt on

    return raw;
}

/// ditto
CppNamespace rawFilter(CppNamespace input, Controller ctrl, Products prod)
in {
    assert(!input.isAnonymous);
    assert(input.name.length > 0);
}
body {
    import std.algorithm : each, filter, map;

    auto ns = CppNamespace.make(input.name);

    // dfmt off
    input.namespaceRange
        .filter!(a => !a.isAnonymous)
        .map!(a => rawFilter(a, ctrl, prod))
        .each!(a => ns.put(a));

    input.classRange
        // ask controller if the file should be processed
        .filter!(a => ctrl.doFile(a.location.file, cast(string) a.name ~ " " ~ a.location.toString))
        .each!(a => ns.put(a));
    //dfmt on

    return ns;
}

void put(UMLCollection uml, CppClass c, Flag!"genClassMethod" class_method,
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
            return tuple(UMLCollection.RelateKey(tkv.type.info.type.strip),
                    UMLCollection.Relate.Kind.Aggregate);
        case Kind.simple:
            if (tkv.type.isRecord && (tkv.type.isPtr || tkv.type.isRef)) {
                return tuple(UMLCollection.RelateKey(tkv.type.info.type.strip),
                        UMLCollection.Relate.Kind.Compose);
            }
            return tuple(UMLCollection.RelateKey(""), UMLCollection.Relate.Kind.None);
        case TypeKind.Info.Kind.func:
            goto case;
        case Kind.array:
            goto case;
        case Kind.funcPtr:
            goto case;
        case Kind.null_:
            return tuple(UMLCollection.RelateKey(""), UMLCollection.Relate.Kind.None);
        }
    }

    static auto getMethodRelation(ref CppClass.CppFunc f) {
        import std.array : array;
        import std.algorithm : among, map;
        import std.variant : visit;
        import std.range : chain, only;
        import std.typecons : TypedefType, Tuple;

        //TODO investigate why strip is needed when analyzing gtest
        import std.string : strip;

        alias Rtuple = Tuple!(UMLCollection.Relate.Kind, "kind", UMLCollection.RelateKey, "key");

        static Rtuple getTypeRelation(TypeKind tk) {
            auto r = Rtuple(UMLCollection.Relate.Kind.None, UMLCollection.RelateKey(""));

            final switch (tk.info.kind) with (TypeKind.Info) {
            case Kind.record:
                r[0] = UMLCollection.Relate.Kind.Associate;
                r[1] = tk.info.type.strip;
                break;
            case Kind.simple:
                if (tk.isRecord && (tk.isPtr || tk.isRef)) {
                    r[0] = UMLCollection.Relate.Kind.Associate;
                    r[1] = tk.info.type.strip;
                }
                break;
            case TypeKind.Info.Kind.func:
                break;
            case Kind.array:
                r[0] = UMLCollection.Relate.Kind.Associate;
                r[1] = tk.info.elementType.strip;
                break;
            case Kind.funcPtr:
                break;
            case Kind.null_:
                break;
            }

            //TODO really ugly, consider some other way of doing this.
            // Copied from translateCursorType.
            // this is hard to keep in sync and error prone.
            // also hard to reuse.
            if ((cast(string) r.key).among("void", "bool", "unsigned char", "unsigned short",
                    "unsigned int", "unsigned long", "unsigned long long", "char", "wchar", "short", "int",
                    "long", "long long", "float", "double", "long double", "null")) {
                r[0] = UMLCollection.Relate.Kind.None;
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

    auto key = UMLCollection.ClassKey(cast(string) c.fullyQualifiedName);

    uml.put(key);

    // dfmt off
    if (class_method) {
        c.methodPublicRange.map!(a => getMethod(a, "+")).each!(a => uml.put(key, a));
    }

    if (class_inherit_dep) {
        c.inheritRange
            .map!(a => UMLCollection.RelateKey(a.fullyQualifiedName.str))
            .each!(a => uml.relate(key, a, UMLCollection.Relate.Kind.Extend));
    }

    if (class_member_dep) {
        c.memberRange
            .map!(a => getMemberRelation(a))
            .filter!(a => a[1] != UMLCollection.Relate.Kind.None)
            .each!(a => uml.relate(key, a[0], a[1]));
    }

    if (class_param_dep) {
        foreach (a; c.methodRange
                 .map!(a => getMethodRelation(a))
                 // flatten the range
                 .joiner()
                 .filter!(a => a.kind != UMLCollection.Relate.Kind.None)
                 // remove self referencing keys, would result in circles which
                 // just clutters the diagrams
                 .filter!(a => a.key != key)) {
            uml.relate(key, a.key, a.kind);
        }
    }
    // dfmt on
}

void translate(CppRoot input, UMLCollection uml, Parameters params) {
    foreach (ref c; input.classRange) {
        put(uml, c, params.genClassMethod, params.genClassParamDependency,
                params.genClassInheritDependency, params.genClassMemberDependency);
    }

    foreach (ref ns; input.namespaceRange) {
        translateNs(ns, uml, params);
    }
}

void translateNs(CppNamespace input, UMLCollection uml, Parameters params) {
    foreach (ref c; input.classRange) {
        put(uml, c, params.genClassMethod, params.genClassParamDependency,
                params.genClassInheritDependency, params.genClassMemberDependency);
    }

    foreach (ref ns; input.namespaceRange) {
        translateNs(ns, uml, params);
    }
}

void generate(UMLCollection uml, Generator.Modules modules) {
    import std.algorithm : each;

    foreach (kv; uml.sortedClassRange) {
        generateClass(kv[0], kv[1], modules.classes);
    }

    generateClassRelate(uml.relateToFlatArray, modules.classes);
}

void generateClass(UMLCollection.ClassKey name, UMLCollection.Class c, PlantumlModule m) {
    import std.algorithm : each;
    import std.array;

    if (c.content.length == 0) {
        m.class_(cast(string) name);
    } else {
        auto content = m.classBody(cast(string) name);
        c.content.each!(a => content.method(a));
    }
}

void generateClassRelate(T)(T relate_range, PlantumlModule m) {
    import std.algorithm : each;

    static auto convKind(UMLCollection.Relate.Kind kind) {
        static import dsrcgen.plantuml;

        final switch (kind) with (UMLCollection.Relate.Kind) {
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
        }
    }

    relate_range.each!(r => m.unsafeRelate(cast(string) r.from, cast(string) r.to, convKind(r.kind)));
}
