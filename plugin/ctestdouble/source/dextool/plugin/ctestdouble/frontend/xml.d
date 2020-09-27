/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.ctestdouble.frontend.xml;

import logger = std.experimental.logger;

static import dextool.xml;

import dextool.compilation_db;
import dextool.type;

import dextool.plugin.ctestdouble.frontend.types;

alias readRawConfig = dextool.xml.readRawConfig!(XmlConfig, parseRawConfig);

/** Store the input in a configuration file to make it easy to regenerate the
 * test double.
 */
ref AppT makeXmlConfig(AppT)(ref AppT app, CompileCommandFilter compiler_flag_filter,
        FilterSymbol restrict_sym, FilterSymbol exclude_sym) {
    import std.algorithm : joiner, copy, map;
    import std.conv : to;
    import std.range : chain;
    import std.xml;
    import dextool.utility : dextoolVersion;
    import dextool.xml : makePrelude;

    auto doc = new Document(new Tag("dextool"));
    doc.tag.attr["version"] = dextoolVersion;
    {
        auto compiler_tag = new Element("compiler_flag_filter");
        compiler_tag.tag.attr["skip_compiler_args"]
            = compiler_flag_filter.skipCompilerArgs.to!string();
        foreach (value; compiler_flag_filter.filter) {
            auto tag = new Element("exclude");
            tag ~= new Text(value);
            compiler_tag ~= tag;
        }
        doc ~= compiler_tag;
    }

    if (restrict_sym.hasSymbols || exclude_sym.hasSymbols) {
        auto symbol_tag = new Element("symbol_filter");
        foreach (value; chain(restrict_sym.range.map!((a) {
                    auto tag = new Element("restrict");
                    tag ~= new Text(a.key);
                    return tag;
                }), exclude_sym.range.map!((a) {
                    auto tag = new Element("exclude");
                    tag ~= new Text(a.key);
                    return tag;
                }))) {
            symbol_tag ~= value;
        }
        doc ~= symbol_tag;
    }

    makePrelude(app);
    doc.pretty(4).joiner("\n").copy(app);

    return app;
}

XmlConfig parseRawConfig(T)(T xml) @trusted {
    import std.conv : to, ConvException;
    import std.xml;

    DextoolVersion version_;
    int skip_flags = 1;
    RawCliArguments command;
    FilterClangFlag[] filter_clang_flags;
    FilterSymbol restrict_symbols;
    FilterSymbol exclude_symbols;

    if (auto tag = "version" in xml.tag.attr) {
        version_ = *tag;
    }

    // dfmt off
    xml.onStartTag["compiler_flag_filter"] = (ElementParser filter_flags) {
        if (auto tag = "skip_compiler_args" in xml.tag.attr) {
            try {
                skip_flags = (*tag).to!int;
            }
            catch (ConvException ex) {
                logger.info(ex.msg);
                logger.info("   using fallback '1'");
            }
        }

        xml.onEndTag["exclude"] = (const Element e) { filter_clang_flags ~= FilterClangFlag(e.text()); };
    };
    xml.onStartTag["symbol_filter"] = (ElementParser filter_sym) {
        xml.onEndTag["restrict"] = (const Element e) { restrict_symbols.put(e.text()); };
        xml.onEndTag["exclude"] = (const Element e) { exclude_symbols.put(e.text()); };
    };
    // dfmt on
    xml.parse();

    return XmlConfig(version_, skip_flags, command, filter_clang_flags,
            restrict_symbols, exclude_symbols);
}

/** Extracted configuration data from an XML file.
 *
 * It is not inteded to be used as is but rather further processed.
 */
struct XmlConfig {
    import dextool.type : DextoolVersion, FilterClangFlag;

    DextoolVersion version_;
    int skipCompilerArgs;
    RawCliArguments command;
    FilterClangFlag[] filterClangFlags;

    /// Only a symbol that matches this
    FilterSymbol restrictSymbols;
    /// Remove symbols matching this
    FilterSymbol excludeSymbols;
}

@("Converted a raw xml config without loosing any configuration data or version")
unittest {
    import unit_threaded : shouldEqual;
    import std.xml;

    string raw = `
<?xml version="1.0" encoding="UTF-8"?>
<dextool version="test">
    <!-- comment is ignored -->
    <command>tag is ignored</command>
    <compiler_flag_filter skip_compiler_args="2">
        <exclude>foo</exclude>
        <exclude>-foo</exclude>
        <exclude>--foo</exclude>
        <exclude>-G 0</exclude>
    </compiler_flag_filter>
</dextool>`;

    auto xml = new DocumentParser(raw);
    auto p = parseRawConfig(xml);

    p.version_.dup.shouldEqual("test");
    p.command.payload.shouldEqual(string[].init);
    p.skipCompilerArgs.shouldEqual(2);
    p.filterClangFlags.shouldEqual([
            FilterClangFlag("foo"), FilterClangFlag("-foo"),
            FilterClangFlag("--foo"), FilterClangFlag("-G 0")
            ]);
}

/// The raw arguments from the command line.
struct RawCliArguments {
    string[] payload;
    alias payload this;
}
