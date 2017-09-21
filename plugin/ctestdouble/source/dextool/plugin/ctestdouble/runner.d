/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.runner;

auto runPlugin(string[] args) {
    import std.array : appender;
    import std.stdio : writeln;
    import dextool.compilation_db;
    import dextool.type;
    import dextool.utility;
    import dextool.xml : makeXmlLog;
    import dextool.plugin.ctestdouble.frontend.ctestdouble;
    import dextool.plugin.ctestdouble.frontend.xml : makeXmlConfig;

    RawConfiguration pargs;
    pargs.parse(args);
    pargs.dump;

    if (pargs.shortPluginHelp) {
        writeln("ctestdouble");
        writeln("generate a C test double. Language is set to C");
        return ExitStatusType.Ok;
    } else if (pargs.help) {
        pargs.printHelp;
        return ExitStatusType.Ok;
    } else if (pargs.invalidXmlConfig) {
        return ExitStatusType.Errors;
    } else if (pargs.inFiles.length == 0) {
        writeln("Missing required argument --in");
        return ExitStatusType.Errors;
    }

    auto variant = CTestDoubleVariant.makeVariant(pargs);
    {
        auto app = appender!string();
        variant.putFile(variant.getXmlLog, makeXmlLog(app, pargs.originalFlags).data);
    }
    {
        auto app = appender!string();
        variant.putFile(variant.getXmlConfigFile, makeXmlConfig(app, variant.getCompileCommandFilter,
                variant.getRestrictSymbols, variant.getExcludeSymbols).data);
    }

    CompileCommandDB compile_db;
    if (pargs.compileDb.length != 0) {
        compile_db = pargs.compileDb.fromArgCompileDb;
    }

    return genCstub(variant, pargs.cflags, compile_db, InFiles(pargs.inFiles));
}
