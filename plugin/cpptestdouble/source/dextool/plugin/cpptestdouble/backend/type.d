/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.cpptestdouble.backend.type;

import cpptooling.data : CppRoot, CppClass, CppMethod, CppCtor, CppDtor, CFunction, CppNamespace;
import cpptooling.data.symbol : USRType;

import dsrcgen.cpp : CppModule, noIndent;

import cpptooling.data.type : CppClassName, CppNs;

import dextool.type : AbsolutePath;

@safe:

enum Kind {
    none,
    /// Adapter class
    adapter,
    /// gmock class
    gmock,
    // generate a pretty print function for the class/struct
    gtestPrettyPrint,
    /// interface for globals
    testDoubleNamespace,
    testDoubleSingleton,
    testDoubleInterface,
}

struct ImplData {
    import cpptooling.data.type : CppMethodName;
    import cpptooling.data.symbol.types : FullyQualifiedNameType;

    CppRoot root;

    IncludeHooks includeHooks;

    /// Tagging of nodes in the root determining how they are handled by the
    /// code generator step.
    Kind[size_t] kind;
    /// Classes found during src analysis.
    CppClass[FullyQualifiedNameType] classes;

    static auto make() {
        return ImplData(CppRoot.make);
    }

    /// Tag an ID with a kind.
    void tag(size_t id, Kind kind_) {
        kind[id] = kind_;
    }

    /// Lookup the tag for an ID.
    Kind lookup(size_t id) {
        if (auto k = id in kind) {
            return *k;
        }

        return Kind.none;
    }

    /// Copy an AA of classes.
    void putForLookup(ref CppClass[FullyQualifiedNameType] other) @trusted {
        foreach (v; other.byKeyValue) {
            classes[v.key] = v.value;
        }
    }

    /// Returns: a range containing the class matching fqn, if found.
    auto lookupClass(FullyQualifiedNameType fqn) @safe {
        import std.range : only;
        import std.typecons : NullableRef;

        typeof(only(NullableRef!CppClass())) rval;
        if (auto c = fqn in classes) {
            rval = only(NullableRef!CppClass(c));
        }

        return rval;
    }
}

struct IncludeHooks {
    AbsolutePath preInclude;
    AbsolutePath postInclude;

    static auto make(T)(T transf) {
        immutable file_cpp_pre_incl = "_pre_includes";
        immutable file_cpp_post_incl = "_post_includes";

        return IncludeHooks(transf.createHeaderFile(file_cpp_pre_incl),
                transf.createHeaderFile(file_cpp_post_incl));
    }
}

struct Code {
    enum Kind {
        hdr,
        impl,
    }

    CppModule cpp;
    alias cpp this;
}

struct Mock {
    // Use to generate a unique filename.
    CppClassName name;
    CppNs[] nesting;

    CppModule cpp;
    alias cpp this;
}

struct GtestPrettyPrint {
    // Use to generate a unique filename.
    CppClassName name;
    CppNs[] nesting;

    CppModule cpp;
    alias cpp this;
}

struct GeneratedData {
    @disable this(this);

    /// Code kinds that can't be duplicated.
    Code[Code.Kind] uniqueData;

    /// All gmocks to write
    Mock[] gmocks;

    GtestPrettyPrint[] gtestPPHdr;
    GtestPrettyPrint[] gtestPPImpl;

    IncludeHooks includeHooks;

    auto make(Code.Kind kind) {
        if (auto c = kind in uniqueData) {
            return *c;
        }

        Code m;
        m.cpp = (new CppModule).noIndent;

        uniqueData[kind] = m;
        return m;
    }

    auto makeMock(CppNs[] ns, CppClassName name) {
        auto m = Mock(name, ns);
        m.cpp = (new CppModule).noIndent;
        gmocks ~= m;

        return m;
    }

    auto makeGtestPrettyPrintHdr(CppNs[] ns, CppClassName name) {
        auto m = GtestPrettyPrint(name, ns);
        m.cpp = (new CppModule).noIndent;
        gtestPPHdr ~= m;

        return m;
    }

    auto makeGtestPrettyPrintImpl(CppNs[] ns, CppClassName name) {
        auto m = GtestPrettyPrint(name, ns);
        m.cpp = (new CppModule).noIndent;
        gtestPPImpl ~= m;

        return m;
    }
}
