module dextool.plugin.runner;

auto runPlugin(string[] args) {
    import std.array : appender;
    import std.stdio : writeln;
    import dextool.compilation_db;
    import dextool.type;
    import dextool.utility;
    import frontend.fuzz.fuzz;
    
    RawConfiguration pargs;
    if(pargs.parse(args) == -1)
        return ExitStatusType.Errors;
    

    if (pargs.shortPluginHelp) {
        writeln("fuzz");
        writeln("generate a C++ fuzz interface. Language is set to C++");
        return ExitStatusType.Ok;
    }

    auto variant = FuzzVariant.makeVariant(pargs);     

    //return ExitStatusType.Ok;
    return genCpp(variant);
}
