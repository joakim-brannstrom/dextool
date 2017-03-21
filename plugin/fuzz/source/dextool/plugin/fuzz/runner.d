module dextool.plugin.runner;

auto runPlugin(string[] args) {
    import std.array : appender;
    import std.stdio : writeln;
    import dextool.compilation_db;
    import dextool.type;
    import dextool.utility;
    import dextool.plugin.frontend.fuzz;
    
    RawConfiguration pargs;
    pargs.parse(args);

    if (pargs.shortPluginHelp) {
        writeln("fuzz");
        writeln("generate a C++ fuzz interface. Language is set to C++");
        return ExitStatusType.Ok;
    }

    //auto variant = fuzzVariant.makeVariant(pargs); // 

    CompileCommandDB compile_db;
    if (pargs.compile_db.length != 0) {
        compile_db = pargs.compile_db.fromArgCompileDb;
    }

    return ExitStatusType.Ok;
    //return genCpp(variant, pargs.cflags, compile_db, InFiles(pargs.inFiles));
}
