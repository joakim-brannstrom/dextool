/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.runner;

import std.typecons : Flag;

auto runPlugin(string[] args) {
    import std.algorithm : map;
    import std.array : appender, array;
    import std.stdio : writeln;
    import dextool.compilation_db;
    import dextool.type;
    import dextool.utility;
    import dextool.plugin.frontend.plantuml;

    RawConfiguration pargs;
    pargs.parse(args);
    pargs.dump;

    if (pargs.shortPluginHelp) {
        writeln("uml");
        writeln("generate PlantUML and GraphViz diagrams");
        return ExitStatusType.Ok;
    } else if (pargs.help) {
        pargs.printHelp;
        return ExitStatusType.Ok;
    }

    auto variant = PlantUMLFrontend.makeVariant(pargs);

    CompileCommandDB compile_db;
    if (pargs.compileDb.length != 0) {
        compile_db = pargs.compileDb.fromArgCompileDb;
    }

    auto skipFileError = cast(Flag!"skipFileError") pargs.skipFileError;

    return genUml(variant, pargs.cflags, compile_db,
            pargs.inFiles.map!(a => Path(a)).array, skipFileError);
}
