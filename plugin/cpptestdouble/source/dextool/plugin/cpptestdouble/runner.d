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
    import logger = std.experimental.logger;
    import dextool.compilation_db;
    import dextool.type;
    import dextool.utility;
    import dextool.xml : makeXmlLog;
    import dextool.plugin.cpptestdouble.frontend : genCpp, CppTestDoubleVariant,
        FrontendTransform, RawConfiguration;
    import dextool.plugin.cpptestdouble.backend : makeXmlConfig;

    RawConfiguration pargs;
    pargs.parse(args);

    debug logger.trace(pargs);

    if (pargs.shortPluginHelp) {
        writeln("cpptestdouble");
        writeln("generate a C++ test double. Language is set to C++");
        return ExitStatusType.Ok;
    } else if (pargs.help) {
        pargs.printHelp;
        return ExitStatusType.Ok;
    } else if (pargs.inFiles.length == 0) {
        writeln("Missing required argument --in (at least one)");
        return ExitStatusType.Errors;
    }

    auto transform = new FrontendTransform(MainFileName(pargs.mainFileName), DirName(pargs.out_));

    auto variant = CppTestDoubleVariant.makeVariant(pargs);
    {
        auto app = appender!string();
        variant.putFile(transform.createXmlFile("_log"), makeXmlLog(app,
                pargs.originalFlags).data);
    }
    {
        auto app = appender!string();
        variant.putFile(transform.createXmlFile("_config"), makeXmlConfig(app,
                variant.getCompileCommandFilter).data);
    }

    CompileCommandDB compile_db;
    if (pargs.compileDb.length != 0) {
        compile_db = pargs.compileDb.fromArgCompileDb;
    }

    return genCpp(variant, transform, pargs.cflags, compile_db, InFiles(pargs.inFiles));
}
