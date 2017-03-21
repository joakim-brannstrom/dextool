module dextool.plugin.runner;

auto runPlugin(string[] args) {
    import std.array : appender;
    import std.stdio : writln;
    import dextool.compilation_db;
    import dextool.type;
    import dextool.utility;
    import dextool.plugin.frontend.fuzz;
    
    RawConfiguration pargs;
    pargs.parse(args);
    pargs.dump;

    if (pargs.shortPluginHelp) {
        writeln("fuzz");
        writeln("generate a C++ fuzz interface. Language is set to C++");
        return ExitStatusType.Ok;
    } else if (pargs.help) {
        pargs.printHelp;
        return ExitStatusType.Ok;
    } else if (pargs.inFiles.length == 0) {
        writeln("Missing required argument --in");
        return ExitStatusType.Errors;
    } else if (pargs.fileExclude.length != 0 && pargs.fileRestrict.length != 0) {
        writeln("Unable to combine both --file-exclude and --file-restrict");
        return ExitStatusType.Errors;
    }

    auto variant = fuzzVariant.makeVariant(pargs);

    CompileCommandDB compile_db;
    if (pargs.compileDb.length != 0) {
        compile_db = pargs.compileDb.fromArgCompileDb;
    }

    return genCpp(variant, pargs.cflags, compile_db, InFiles(pargs.inFiles));
}
