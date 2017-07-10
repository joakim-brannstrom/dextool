/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.cpptestdouble.backend.generate_cpp;

import cpptooling.data.representation : CppNamespace;
import cpptooling.data.type : LocationTag;
import cpptooling.data.symbol.container : Container;

import dsrcgen.cpp : CppModule;

import dextool.plugin.cpptestdouble.backend.interface_ : Controller, Parameters;
import dextool.plugin.cpptestdouble.backend.type : Code, GeneratedData,
    ImplData, Kind;

/** Translate the structure to code.
 *
 * Generates:
 *  - #include's needed by the test double
 *  - recursive starting with the root:
 *    order is important, affects code layout:
 *      - anonymouse instance of the adapter for the test double
 *      - free function implementations using the registered test double
 *      - adapter registering a test double instance
 */
void generate(ref ImplData impl, Controller ctrl, Parameters params,
        ref GeneratedData gen_data, ref const Container container) {
    import std.algorithm : filter;
    import std.path : baseName;
    import cpptooling.generator.includes : generateIncludes;
    import cpptooling.generator.func : generateFuncImpl;
    import cpptooling.generator.gmock : generateGmock;

    if (ctrl.doPreIncludes) {
        gen_data.make(Code.Kind.hdr).include(impl.includeHooks.preInclude.baseName);
    }

    generateIncludes(params.getIncludes, gen_data.make(Code.Kind.hdr));

    if (ctrl.doPostIncludes) {
        gen_data.make(Code.Kind.hdr).include(impl.includeHooks.postInclude.baseName);
    }

    foreach (a; impl.root.classRange.filter!(a => impl.lookup(a.id) == Kind.gmock)) {
        generateGmock(a, gen_data.make(Code.Kind.gmock), params);
    }

    // the singletons are collected at the top and only one of it.
    auto td_singleton = gen_data.make(Code.Kind.impl).base;
    td_singleton.suppressIndent(1);

    foreach (a; impl.root.funcRange) {
        generateFuncImpl(a, gen_data.make(Code.Kind.impl));
    }

    auto ns_data = GenerateNamespaceData(gen_data.make(Code.Kind.hdr),
            gen_data.make(Code.Kind.impl), gen_data.make(Code.Kind.gmock));
    foreach (a; impl.root.namespaceRange()) {
        generateForEach(impl, a, params, ns_data, td_singleton, container);
    }
}

private:

struct GenerateNamespaceData {
    CppModule hdr;
    CppModule impl;
    CppModule gmock;
}

/**
 * recursive to handle nested namespaces.
 * the singleton ns must be the first code generate or the impl can't use the
 * instance.
 */
void generateForEach(ref ImplData impl, ref CppNamespace ns, Parameters params,
        GenerateNamespaceData gen_data, CppModule impl_singleton, ref const Container container) {
    import cpptooling.data.symbol.types : USRType;
    import cpptooling.generator.func : generateFuncImpl;
    import cpptooling.generator.gmock : generateGmock;

    GenerateNamespaceData inner = gen_data;
    CppModule inner_impl_singleton = impl_singleton;

    switch (impl.lookup(ns.id)) with (Kind) {
    case none:
        //TODO how to do this with meta-programming?
        inner.hdr = gen_data.hdr.namespace(ns.name);
        inner.hdr.suppressIndent(1);
        inner.impl = gen_data.impl.namespace(ns.name);
        inner.impl.suppressIndent(1);
        inner.gmock = gen_data.gmock.namespace(ns.name);
        inner.gmock.suppressIndent(1);
        inner_impl_singleton = inner.impl.base;
        inner_impl_singleton.suppressIndent(1);
        break;
    case testDoubleSingleton:
        import dextool.plugin.backend.cpptestdouble.adapter : generateSingleton;

        generateSingleton(ns, impl_singleton);
        break;
    case testDoubleInterface:
        break;
    case testDoubleNamespace:
        generateNsTestDoubleHdr(ns, params, gen_data.hdr, gen_data.gmock,
                (USRType usr) => container.find!LocationTag(usr), impl);
        generateNsTestDoubleImpl(ns, gen_data.impl, impl);
        break;
    default:
        break;
    }

    foreach (a; ns.funcRange) {
        generateFuncImpl(a, inner.impl);
    }

    foreach (a; ns.namespaceRange) {
        generateForEach(impl, a, params, inner, inner_impl_singleton, container);
    }
}

void generateNsTestDoubleHdr(LookupT)(CppNamespace ns, Parameters params,
        CppModule hdr, CppModule gmock, LookupT lookup, ref ImplData data) {
    import std.typecons : Yes, No;
    import cpptooling.generator.classes : generateHdr;
    import cpptooling.generator.gmock : generateGmock;

    auto cpp_ns = hdr.namespace(ns.name);
    cpp_ns.suppressIndent(1);
    hdr.sep(2);

    foreach (c; ns.classRange()) {
        switch (data.lookup(c.id)) {
        case Kind.none:
            generateHdr(c, cpp_ns, No.locationAsComment, lookup, Yes.inlineDtor);
            break;
        case Kind.testDoubleInterface:
            generateHdr(c, cpp_ns,
                    No.locationAsComment, lookup, Yes.inlineDtor);
            break;
        case Kind.adapter:
            generateHdr(c, cpp_ns, No.locationAsComment, lookup);
            break;
        case Kind.gmock:
            generateGmock(c, gmock, params);
            break;
        default:
            break;
        }
    }
}

void generateNsTestDoubleImpl(CppNamespace ns, CppModule impl, ref ImplData data) {
    import std.algorithm : each;
    import dextool.plugin.backend.cpptestdouble.adapter : generateImpl;

    auto cpp_ns = impl.namespace(ns.name);
    cpp_ns.suppressIndent(1);
    impl.sep(2);

    foreach (ref class_; ns.classRange()) {
        switch (data.lookup(class_.id)) {
        case Kind.adapter:
            generateImpl(class_, cpp_ns);
            break;
        default:
            break;
        }
    }
}
