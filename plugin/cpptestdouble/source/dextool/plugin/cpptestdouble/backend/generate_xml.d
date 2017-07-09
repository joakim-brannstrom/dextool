/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.cpptestdouble.backend.generate_xml;

import dextool.compilation_db : CompileCommandFilter;

/** Store the input in a configuration file to make it easy to regenerate the
 * test double.
 */
ref AppT makeXmlLog(AppT)(ref AppT app, string[] raw_cli_flags,) {
    import std.algorithm : joiner, copy;
    import std.array : array;
    import std.file : thisExePath;
    import std.format : format;
    import std.path : baseName;
    import std.utf : byChar;
    import std.xml;
    import dextool.utility : dextoolVersion;
    import dextool.xml : makePrelude;

    auto doc = new Document(new Tag("dextool"));
    doc.tag.attr["version"] = dextoolVersion;
    {
        auto command = new Element("command");
        command ~= new CData(format("%s %s", thisExePath.baseName,
                raw_cli_flags.joiner(" ").byChar.array().idup));
        doc ~= new Comment("command line when dextool was executed");
        doc ~= command;
    }

    makePrelude(app);
    doc.pretty(4).joiner("\n").copy(app);

    return app;
}

/** Store the input in a configuration file to make it easy to regenerate the
 * test double.
 */
ref AppT makeXmlConfig(AppT)(ref AppT app, CompileCommandFilter compiler_flag_filter) {
    import std.algorithm : joiner, copy;
    import std.conv : to;
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

    makePrelude(app);
    doc.pretty(4).joiner("\n").copy(app);

    return app;
}
