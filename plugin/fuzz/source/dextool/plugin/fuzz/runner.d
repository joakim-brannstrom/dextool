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

    auto variant = FuzzVariant.makeVariant(pargs);     

    //return ExitStatusType.Ok;
    return genCpp(variant);
}
