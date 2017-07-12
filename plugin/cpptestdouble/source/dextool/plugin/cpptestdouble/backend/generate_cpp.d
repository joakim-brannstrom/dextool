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
import cpptooling.data.type : LocationTag, CppNs, CppClassName;
import cpptooling.data.symbol.container : Container;

import dsrcgen.cpp : CppModule, noIndent;

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

    // dfmt off
    auto ns_data = GenerateNamespaceData(
        () { return gen_data.make(Code.Kind.hdr).cpp.base.noIndent; },
        () { return gen_data.make(Code.Kind.impl).cpp.base.noIndent; },
        (const CppNs[] ns, const CppClassName name) { return gen_data.makeMock(ns, name).cpp.base.noIndent; });
    // dfmt on

    foreach (a; impl.root.classRange.filter!(a => impl.lookup(a.id) == Kind.gmock)) {
        auto mock_ns = ns_data.gmock(cast(const CppNs[]) a.resideInNs, a.name)
            .base.namespace(params.getMainNs).noIndent;
        generateGmock(a, mock_ns);
    }

    foreach (a; impl.root.funcRange) {
        generateFuncImpl(a, ns_data.impl().base);
    }

    foreach (a; impl.root.namespaceRange()) {
        generateForEach(impl, a, params, ns_data, container);
    }
}

private:

alias LazyModule = CppModule delegate() @safe;
alias LazyMockModule = CppModule delegate(const CppNs[] ns, const CppClassName name) @safe;

/// Lazily create the modules when they are needed.
/// Be wary that each time a LazyModule is called it may generate code.
@safe struct GenerateNamespaceData {
    this(LazyModule hdr, LazyModule impl, LazyMockModule gmock) {
        this.hdr = () => hdr().base.noIndent;
        this.impl_ = impl;
        this.gmock = (const CppNs[] ns, const CppClassName name) => gmock(ns, name).base.noIndent;
        this.impl = () => this.makeImpl().base.noIndent;
        this.implTop = () => this.makeImplTop().base.noIndent;
    }

    LazyModule hdr;
    LazyMockModule gmock;
    LazyModule impl;
    LazyModule implTop;

private:
    /// Position at the top of the implementation file where e.g. globals go.
    CppModule makeImplTop() {
        if (impl_top is null) {
            auto b = impl_().noIndent;
            impl_top = b.base.noIndent;
            impl_mod = b.base.noIndent;
        }
        return impl_top;
    }

    CppModule makeImpl() {
        makeImplTop;
        return impl_mod;
    }

    LazyModule impl_;
    CppModule impl_top;
    CppModule impl_mod;
}

/**
 * recursive to handle nested namespaces.
 * the singleton ns must be the first code generate or the impl can't use the
 * instance.
 */
void generateForEach(ref ImplData impl, ref CppNamespace ns, Parameters params,
        GenerateNamespaceData gen_data, ref const Container container) {
    import cpptooling.data.symbol.types : USRType;
    import cpptooling.generator.func : generateFuncImpl;

    auto ns_data = GenerateNamespaceData(gen_data.hdr, gen_data.impl, gen_data.gmock);

    switch (impl.lookup(ns.id)) with (Kind) {
    case none:
        auto hdrMod() {
            return gen_data.hdr().namespace(ns.name).noIndent;
        }

        auto implMod() {
            return gen_data.impl().namespace(ns.name).noIndent;
        }

        auto gmockMod(const CppNs[] nesting, const CppClassName name) {
            return gen_data.gmock(nesting, name).namespace(ns.name).noIndent;
        }

        ns_data = GenerateNamespaceData(&hdrMod, &implMod, &gmockMod);
        break;
    case testDoubleSingleton:
        import dextool.plugin.backend.cpptestdouble.adapter : generateSingleton;

        // inject the singleton in the previous top position
        generateSingleton(ns, gen_data.implTop());
        break;
    case testDoubleInterface:
        break;
    case testDoubleNamespace:
        generateNsTestDoubleHdr(ns, params, ns_data.hdr, ns_data.gmock,
                (USRType usr) => container.find!LocationTag(usr), impl);
        generateNsTestDoubleImpl(ns, ns_data.impl, impl);
        break;
    default:
        break;
    }

    foreach (a; ns.funcRange) {
        generateFuncImpl(a, ns_data.impl().base);
    }

    foreach (a; ns.namespaceRange) {
        generateForEach(impl, a, params, ns_data, container);
    }
}

void generateNsTestDoubleHdr(LookupT)(CppNamespace ns, Parameters params,
        LazyModule hdr_, LazyMockModule gmock, LookupT lookup, ref ImplData data) {
    import std.typecons : Yes, No;
    import cpptooling.generator.classes : generateHdr;
    import cpptooling.generator.gmock : generateGmock;

    CppModule ns_cache;

    auto cppNs() {
        if (ns_cache is null) {
            auto hdr = hdr_();
            ns_cache = hdr.namespace(ns.name).noIndent;
            hdr.sep(2);
        }
        return ns_cache.base;
    }

    foreach (c; ns.classRange()) {
        switch (data.lookup(c.id)) {
        case Kind.none:
            generateHdr(c, cppNs(), No.locationAsComment, lookup, Yes.inlineDtor);
            break;
        case Kind.testDoubleInterface:
            generateHdr(c, cppNs(),
                    No.locationAsComment, lookup, Yes.inlineDtor);
            break;
        case Kind.adapter:
            generateHdr(c, cppNs(), No.locationAsComment, lookup);
            break;
        case Kind.gmock:
            auto mock_ns = gmock(c.resideInNs, c.name)
                .base.namespace(params.getMainNs).noIndent;
            generateGmock(c, mock_ns);
            break;
        default:
            break;
        }
    }
}

void generateNsTestDoubleImpl(CppNamespace ns, LazyModule impl_, ref ImplData data) {
    import dextool.plugin.backend.cpptestdouble.adapter : generateImpl;

    CppModule cpp_ns;
    auto cppNs() {
        if (cpp_ns is null) {
            auto impl = impl_();
            cpp_ns = impl.namespace(ns.name);
            impl.sep(2);
        }
        return cpp_ns;
    }

    foreach (ref class_; ns.classRange()) {
        switch (data.lookup(class_.id)) {
        case Kind.adapter:
            generateImpl(class_, cppNs());
            break;
        default:
            break;
        }
    }
}
