module frontend.fuzz.fuzz;

import logger = std.experimental.logger;

import backend.fuzz.fuzzvariant : Parameters,
    Products;
import backend.fuzz.types;

import dextool.plugin.types;
import dextool.type;
import dextool.type;
import dextool.utility;
import dextool.compilation_db;

import compidb;
import xml_parse;

//Search and get headers from specific file
auto getHeaderFiles(CompileCommandDB compile_db, CompileCommand file) @safe {
    import std.range : array;
    import std.algorithm : uniq, filter, map, sort;
    import std.file : dirEntries, SpanMode;
    import std.conv : to;

    string[] flags = parseFlag(file, defaultCompilerFilter).filter!(a => a[0] != '-').array;
    string[] files;

    foreach(dir ; flags) { //Should return every directory
        files ~= () @trusted { return dirEntries(dir, "*_factory.{h,hpp}", SpanMode.breadth).map!(a => to!string(a)).array; } ();
    }
    return files.array;
}

auto getHeaderFiles(CompileCommandDB compile_db) @safe {
    import std.algorithm : uniq, sort;
    import std.range : array;

    string[] hfiles;
    foreach(cmd ; compile_db) {
        hfiles ~= compile_db.getHeaderFiles(cmd);
    }

    return hfiles.sort().uniq.array;
}

struct RawConfiguration {
    string[] xml_dir; //Base directory which contains XML interfaces
    string[] compile_db;
    string output_dir;
    string mainFileName = "fuzz";
    string app_name;


    /* Predefined error messages, used for showing user */
    string XML_ARG_MISSING = "Missing xml-dir as argument";
    string COMPILE_DB_MISSING = "Missing compile-db as argument";

    string help_msg = "Usage: dextool fuzz --compile-db=... --xml-dir=...";

    bool shortPluginHelp;

    /*
    * Parses arguments from terminal
    * @param args Equal to argv
    */
    int parse(string[] args) {
        import std.getopt;
        import std.stdio : writeln;
        try {
            auto helpInformation = getopt(args, std.getopt.config.keepEndOfOptions,
                    "xml-dir", "Base directories to XML interfaces", &xml_dir,
                    "compile-db", "Base directories to compilation databases", &compile_db,
                    "out", "Output directory", &output_dir,
                    "main-fname", &mainFileName,
                    "app-name", &app_name,
                    "short-plugin-help", &shortPluginHelp);
            
            if (helpInformation.helpWanted) {
                defaultGetoptPrinter("Usage.",
                    helpInformation.options);
                return -1;
            }

            /* Check default arguments */
            if(!shortPluginHelp && xml_dir.length == 0) {
                defaultGetoptPrinter(XML_ARG_MISSING,
                    helpInformation.options);
                return -1;
            }

            if(!shortPluginHelp && compile_db.length == 0) {
                defaultGetoptPrinter(COMPILE_DB_MISSING,
                    helpInformation.options);
                return -1;
            }

            if(!shortPluginHelp && app_name.length == 0) {
                defaultGetoptPrinter("app-name missing.",
                    helpInformation.options);
                return -1;
            }

        } catch(GetOptException ex) {
            logger.error("ERROR: " ~ ex.msg);
            return -1;
        }

        return 0;
    }
}

struct FileData {
    import dextool.type : FileName;

    FileName filename;
    string data;
}


class FuzzVariant : Parameters, Products {
    import dextool.type : FileName, DirName, MainName, StubPrefix, DextoolVersion,
        CustomHeader, MainNs, MainInterface;
    import dextool.utility;
    import dsrcgen.cpp;



    private {
        static const hdrExt = ".hpp";
        static const implExt = ".cpp";
        static const xmlExt = ".xml";

        StubPrefix prefix;

        AppName app_name;

        DirName output_dir;
        FileName main_file_hdr;
        FileName main_file_impl;
        FileName main_file_main;       
        FileName main_file_main_hdr;        

        MainName main_name;
        MainNs main_ns;
        MainInterface main_if;

        BaseDir[] xml_dir;
        CompileCommandDB compile_db;
        string compile_db_name;
        
        FileName[] includes;
        FileData[] file_data;
    }

    static auto makeVariant(ref RawConfiguration conf) {
        auto variant = new FuzzVariant(MainFileName(conf.mainFileName), conf.xml_dir, conf.compile_db, DirName(conf.output_dir), AppName(conf.app_name));

        return variant;
    }

    this(MainFileName main_fname, string[] xml_dir, string[] compile_db,
            DirName output_dir, AppName app_name) {
        import std.path : baseName, buildPath, stripExtension;

        this.output_dir = output_dir;

        string base_filename = cast(string) main_fname;

        this.main_file_hdr = FileName(buildPath(cast(string) output_dir, base_filename ~ hdrExt));
        this.main_file_impl = FileName(buildPath(cast(string) output_dir, base_filename ~ implExt));
        this.main_file_main = FileName(buildPath(cast(string) output_dir,
                "main" ~ implExt));
        this.main_file_main_hdr = FileName(buildPath(cast(string) output_dir,
                "main" ~ hdrExt));

        this.app_name = app_name;

        if(xml_dir.length == 0)
            return;
        if(compile_db.length == 0)
            return;
        foreach(dir ; xml_dir) {
            this.xml_dir ~= BaseDir(dir);
        }
        this.compile_db = compile_db.fromArgCompileDb;
        this.compile_db_name = compile_db[0];
    }

    //Parameter functionis
    @safe string[] getIncludes() {
        import std.algorithm : map, uniq, sort;
        import std.range : array;
        import std.path : baseName;
        import std.stdio;

        return this.compile_db.getHeaderFiles.array;
    }
    
    Parameters.Files getFiles() {
        return Parameters.Files(main_file_hdr, main_file_impl,
                main_file_main, main_file_main_hdr);
    }

    MainName getMainName() {
        return main_name;
    }

    AppName getAppName() {
        return app_name;
    }

    MainNs getMainNs() {
        return main_ns;
    }

    MainInterface getMainInterface() {
        return main_if;
    }

    StubPrefix getArtifactPrefix() {
        return prefix;
    }

    DextoolVersion getToolVersion() {
        import dextool.utility : dextoolVersion;

        return dextoolVersion;
    }

    CustomHeader getCustomHeader() {
        return CustomHeader("");
    }

    BaseDir[] getXMLBasedir() {
        return this.xml_dir;
    }

    CompileCommandDB getCompileDB() {
        return this.compile_db;
    }

    string getCompileDBName() {
        return this.compile_db_name;
    }

    //Product functions
    void putFile(FileName fname, CppHModule hdr_data) {
        file_data ~= FileData(fname, hdr_data.render());
    }

    void putFile(FileName fname, CppModule impl_data) {
        file_data ~= FileData(fname, impl_data.render());
    }
}

ExitStatusType genCpp(FuzzVariant variant) {
    import std.path : buildNormalizedPath, asAbsolutePath;
    import std.typecons : Yes;
    import std.algorithm : canFind, joiner;
    import std.file : write;
    import std.conv : to;

    import cpptooling.analyzer.clang.context : ClangContext;
    import cpptooling.data.representation : CppRoot;
    import dextool.compilation_db : defaultCompilerFlagFilter;
    import backend.fuzz.fuzzvariant : Generator,
        FuzzVisitor;
    import dextool.io : writeFileData;

    auto visitor = new FuzzVisitor!(CppRoot, Products)(variant);
    string[] use_cflags;
    string[] in_cflags;
    auto user_cflags = prependDefaultFlags(in_cflags, "");

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    //
    string[] analyzed_files;
    foreach(cmd; variant.getCompileDB) {
        auto hfiles = variant.getCompileDB.getHeaderFiles(cmd);
        auto db_search_result = variant.getCompileDB.appendOrError(user_cflags, cmd.absoluteFile,
                CompileCommandFilter(defaultCompilerFlagFilter, 1));

        if (db_search_result.isNull) {
            return ExitStatusType.Errors;
        }
        
        use_cflags = db_search_result.get.cflags;

        foreach(hfile ; hfiles) {
            if (analyzed_files.canFind(hfile)) {
                continue;
            }

            if (analyzeFile(hfile, use_cflags, visitor, ctx) == ExitStatusType.Errors) {
                return ExitStatusType.Errors;
            }
            analyzed_files ~= hfile;
            
            // Maybe move rawFilter (now in process) to a new function for less memory? Do some memory checks perhaps
            
        }
    }

    auto gen = Generator(variant, variant);
    gen.process(visitor.root, visitor.container);

    debug {
        logger.trace(visitor);
    }

    writeFileData(variant.file_data);

    CompilationDatabase comp_db = parse(CDBFileName(variant.getCompileDBName));
    Makefile mkfile = toMakefile(comp_db, true);
    Compiler cc = getCompiler(mkfile);
    mkfile.rules ~= MakefileRule(RuleName("fuzz_main"), 
            Command("clang++ " ~ to!string(mkfile.outputs.joiner(" ")) ~ " fuzz.cpp main.cpp fuzz_out/portenvironment.cpp fuzz_out/portstorage.cpp fuzz_out/mt1337.cpp fuzz_out/testingenvironment.cpp"));
    mkfile.rules_name ~= RuleName("fuzz_main");
    write("Makefile_fuzz", (generate(mkfile)));

    return ExitStatusType.Ok;
}
