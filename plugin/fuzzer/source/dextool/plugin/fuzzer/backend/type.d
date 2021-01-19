/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.fuzzer.backend.type;

public import cpptooling.data.symbol.types : FullyQualifiedNameType;
import cpptooling.data : CppRoot;

import dextool.plugin.fuzzer.backend.unique_sequence : Sequence;
import dextool.type : Path;

import dsrcgen.cpp : CppModule;

@safe:

/** Analyzed data transformed to implementation.
 *
 * The abstraction is still _high_.
 */
struct ImplData {
    import dextool.plugin.fuzzer.type : Symbol, FullyQualifiedNameType, Param;

    @disable this(this);

    /// DOM
    CppRoot root;

    /// All symbols specified in the user configuration.
    Symbol[FullyQualifiedNameType] symbols;

    /// User specified symbols to ignore.
    IgnoreSymbol[] excludedSymbols;

    /// ID's for all symbols, both user specified and newly discovered.
    ulong[FullyQualifiedNameType] symbolId;

    static auto make() {
        return ImplData(CppRoot.make);
    }
}

struct IgnoreSymbol {
    FullyQualifiedNameType payload;
    alias payload this;
}

struct Code {
    enum Kind {
        main,
        fuzzy,
        configTemplate,
    }

    CppModule cpp;
    ubyte[] fuzzyData;
}

/** Encapsulate the xml data that is used to generate the prettified string to
 * be written to the filesystem.
 *
 * Responsible for storing the xml-data and stringification.
 * Nothing else.
 */
struct TemplateConfig {
    import std.xml : Document, Element;

    @disable this(this);

    Document doc;
    Element symbols;

    static auto make() @trusted {
        import std.xml;
        import dextool.utility : dextoolVersion;

        TemplateConfig r;
        r.doc = new Document(new Tag("dextool"));
        r.doc.tag.attr["version"] = dextoolVersion.get;
        r.symbols = new Element("symbols");
        r.doc ~= r.symbols;
        return r;
    }

    /// TODO change to @safe when the base compiler is upgraded to 2.074+
    Element makeSymbol() @trusted {
        auto elem = new Element("symbol");
        symbols ~= elem;
        return elem;
    }

    void put(T)(ref T app) {
        import std.algorithm : joiner, copy;
        import dextool.xml : makePrelude;

        makePrelude(app);
        () @trusted { doc.pretty(4).joiner("\n").copy(app); }();
    }
}

struct GeneratedData {
    @disable this(this);

    Code[Code.Kind] data;
    TemplateConfig templateConfig;
    FuzzCase[] fuzzCases;

    /// TODO change to a template to be able to handle making _any_ kind of _data_.
    auto make(Code.Kind kind) {
        if (auto c = kind in data) {
            return *c;
        }

        Code m;

        final switch (kind) {
        case Code.Kind.main:
            m.cpp = new CppModule;
            break;
        case Code.Kind.fuzzy:
            m.cpp = new CppModule;
            break;
        case Code.Kind.configTemplate:
            templateConfig = TemplateConfig.make;
            break;
        }

        data[kind] = m;
        return m;
    }
}

struct FuzzCase {
    /// the root of the file content.
    CppModule cpp;
    /// Includes are placed here, before the content of the body
    CppModule includes;
    /// The inside of the generated FUZZ_TEST(...) {... }
    CppModule body_;
    Path filename;
    ulong testCaseId;
}

struct DextoolHelperRawData {
    string payload;
    alias payload this;
}

struct Prefix {
    string payload;
    alias payload this;
}

struct DextoolHelperFile {
    string payload;
    alias payload this;
}
