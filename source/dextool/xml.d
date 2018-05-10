/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Helper functions for xml reading and writing.
*/
module dextool.xml;

import std.typecons : Nullable;

import logger = std.experimental.logger;

import dextool.type : FileName;

/// Generate the xml prelude.
void makePrelude(AppT)(ref AppT app) {
    import std.format : formattedWrite;

    formattedWrite(app, `<?xml version="1.0" encoding="UTF-8"?>` ~ "\n");
}

/// Parse an xml file.
Nullable!T readRawConfig(T, alias parseFunc)(FileName fname) @trusted nothrow {
    static import std.file;
    import std.utf : validate;
    import std.xml;

    string msg;
    Nullable!T rval;

    try {
        string fin = cast(string) std.file.read(fname);
        validate(fin);
        check(fin);
        auto xml = new DocumentParser(fin);

        rval = parseFunc(xml);
        return rval;
    } catch (CheckException ex) {
        try {
            msg = ex.toString;
        } catch (Exception ex) {
            msg = ex.msg;
        }
    } catch (Exception ex) {
        msg = ex.msg;
    }

    try {
        logger.errorf("Invalid xml file '%s'", cast(string) fname);
        logger.error(msg);
    } catch (Exception ex) {
    }

    return rval;
}

/** Store the input in a configuration file to make it easy to regenerate the
 * test double.
 */
ref AppT makeXmlLog(AppT)(ref AppT app, string[] raw_cli_flags,) {
    import std.algorithm : joiner, copy, splitter;
    import std.array : array;
    import std.file : thisExePath;
    import std.format : format;
    import std.path : baseName;
    import std.range : dropOne, drop, takeOne;
    import std.utf : byChar;
    import std.xml;
    import dextool.utility : dextoolVersion;
    import dextool.xml : makePrelude;

    auto exe_r = thisExePath.baseName.splitter('-');

    auto exe_name = "dextool";
    foreach (a; exe_r.save.takeOne) {
        exe_name = a;
    }

    auto plugin_name = "unknown_plugin";
    foreach (a; exe_r.save.dropOne) {
        plugin_name = a;
    }

    auto cleaned_cli = raw_cli_flags.drop(2);

    auto doc = new Document(new Tag("dextool"));
    doc.tag.attr["version"] = dextoolVersion;
    {
        auto command = new Element("command");
        command ~= new CData(format("%s %s %s", exe_name, plugin_name,
                cleaned_cli.joiner(" ").byChar.array().idup));
        doc ~= new Comment("command line when dextool was executed");
        doc ~= command;
    }

    makePrelude(app);
    doc.pretty(4).joiner("\n").copy(app);

    return app;
}
