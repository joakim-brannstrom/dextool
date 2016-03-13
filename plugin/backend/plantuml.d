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

import std.typecons : Typedef, Tuple;
import logger = std.experimental.logger;

import dsrcgen.plantuml;

import application.types;

/// Control various aspectes of the analyze and generation like what nodes to
/// process.
@safe interface Controller {
    /// Query the controller with the filename of the AST node for a decision
    /// if it shall be processed.
    bool doFile(in string filename, in string info);
}

/// Parameters used during generation.
/// Important aspact that they do NOT change, therefore it is pure.
@safe pure interface Parameters {
    import std.typecons : Tuple;

    alias Files = Tuple!(FileName, "component");

    /// Output directory to store files in.
    DirName getOutputDirectory();

    /// Files to write generated test double data to.
    Files getFiles();

    /// Name affecting interface, namespace and output file.
    MainName getMainName();
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

struct Generator {
    import cpptooling.data.representation : CppRoot;
    import cpptooling.data.symbol.container : Container;

    static struct Modules {
        PlantumlModule component;

        static auto make() {
            Modules m;

            //TODO how to do this with meta-programming and instrospection fo Modules?
            m.component = new PlantumlModule;

            return m;
        }
    }

    this(Controller ctrl, Parameters params, Products products) {
        this.ctrl = ctrl;
        this.params = params;
        this.products = products;
    }

    auto process(ref CppRoot root, ref Container container) {
        import cpptooling.data.representation : CppNamespace, CppNs;

        logger.trace("Raw:\n" ~ root.toString());

        auto fl = rawFilter(root, ctrl, products);
        logger.trace("Filtered:\n" ~ fl.toString());

        //auto tr = translate(fl, container, ctrl, params);
        //logger.trace("Translated to essentials for UML:\n" ~ tr.toString());

        auto m = Modules.make();
        generate(fl, ctrl, params, m);
        postProcess(ctrl, params, products, m);
    }

private:
    Controller ctrl;
    Parameters params;
    Products products;

    static void postProcess(Controller ctrl, Parameters params, Products prods, Modules m) {
        static auto output(PlantumlModule pm) {
            auto proot = PlantumlRootModule.make();
            proot.content.append(pm);

            return proot;
        }

        prods.putFile(params.getFiles.component, output(m.component));
    }
}

private:
@safe:

import cpptooling.data.representation : CppRoot, CppClass, CppMethod, CppCtor,
    CppDtor, CFunction, CppNamespace, CxLocation;
import dsrcgen.plantuml;

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

/** Translate the structure to a plantuml diagram.
 */
void generate(CppRoot r, Controller ctrl, Parameters params, Generator.Modules modules)
in {
    assert(r.funcRange.empty);
}
body {
    import std.algorithm : each;

    // dfmt off
    r.classRange
        .each!(a => generateComponent(a, modules.component));

    r.namespaceRange
        .each!(a => generate(a, ctrl, params, modules));
    // dfmt on
}

void generate(CppNamespace ns, Controller ctrl, Parameters params, Generator.Modules modules) {
    import std.algorithm : each;

    // dfmt off
    ns.classRange
        .each!(a => generateComponent(a, modules.component));

    ns.namespaceRange
        .each!(a => generate(a, ctrl, params, modules));
    // dfmt on
}

import cpptooling.utility.conv : str;

void generateComponent(CppClass c, PlantumlModule m) {
    import std.algorithm : each;
    import cpptooling.data.representation;

    static void genMethod(T0, T1)(T0 uml_c, T1 method_, string prefix) @trusted {
        import std.variant : visit;

        method_.visit!((CppMethod m) => uml_c.method(prefix ~ m.toString),
                (CppMethodOp m) => uml_c.method(prefix ~ m.toString),
                (CppCtor m) => uml_c.method(prefix ~ m.toString),
                (CppDtor m) => uml_c.method(prefix ~ m.toString));

    }

    static void genInheritRelation(T)(T uml, string parent, CppInherit inherit) {
        uml.unsafeRelate(parent, inherit.fullyQualifiedName.str, Relate.Extend);
    }

    static void genCompositionRelation(T)(T uml, string parent, TypeKindVariable tkv) {
        import std.string : stripRight;

        // move filtering to rawFilter
        final switch (tkv.type.info.kind) with (TypeKind.Info) {
        case Kind.record:
            uml.unsafeRelate(parent, tkv.type.toString("")
                    .stripRight, Relate.Aggregate);
            break;
        case Kind.simple:
            break;
        case Kind.array:
            break;
        case Kind.funcPtr:
            break;
        case Kind.null_:
            break;
        }
    }

    auto uml_c = m.classBody(c.fullyQualifiedName.str);
    c.methodPublicRange.each!(a => genMethod(uml_c, a, "+"));
    c.inheritRange.each!(a => genInheritRelation(m, c.fullyQualifiedName.str, a));
    c.memberRange.each!(a => genCompositionRelation(m, c.fullyQualifiedName.str, a));
}
