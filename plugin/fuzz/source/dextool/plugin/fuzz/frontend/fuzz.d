module dextool.plugin.frontend.fuzz;

import logger = std.experimental.logger;

import dextool.plugin.backend.fuzz.fuzzvariant : Parameters,
    Products;
import dextool.plugin.types;
import dextool.type;
import dextool.type;
import dextool.utility;
import dextool.compilation_db;


import xml_parse;

//Search and get headers from specific file
auto getHeaderFiles(CompileCommandDB compile_db, CompileCommand file) @safe {
    import std.range : array;
    import std.algorithm : uniq, filter, map, sort;
    import std.file : dirEntries, SpanMode;
    import std.conv : to;

    string[] flags = parseFlag(file, CompileCommandFilter()).filter!(a => a[0] != '-').array;
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


    /* Predefined error messages, used for showing user */
    string XML_ARG_MISSING = "Missing xml-dir as argument";
    string COMPILE_DB_MISSING = "Missing compile-db as argument";

    string help_msg = "Usage: dextool fuzz --compile-db=... --xml-dir=...";

    bool shortPluginHelp;

    /*
    * Parses arguments from terminal
    * @param args Equal to argv
    */
    void parse(string[] args) {
        import std.getopt;
        import std.stdio : writeln;
        try {
            auto helpInformation = getopt(args, std.getopt.config.keepEndOfOptions,
                    "xml-dir", "Base directories to XML interfaces", &xml_dir,
                    "compile-db", "Base directories to compilation databases", &compile_db,
                    "out", "Output directory", &output_dir,
                    "main-fname", &mainFileName,
                    "short-plugin-help", &shortPluginHelp);
            
            if (helpInformation.helpWanted) {
                defaultGetoptPrinter("Usage.",
                    helpInformation.options);
                return;
            }

            /* Check default arguments */
            if(!shortPluginHelp && xml_dir.length == 0) {
                defaultGetoptPrinter(XML_ARG_MISSING,
                    helpInformation.options);
                return;
            }

            if(!shortPluginHelp && compile_db.length == 0) {
                defaultGetoptPrinter(COMPILE_DB_MISSING,
                    helpInformation.options);
                return;
            }

        } catch(GetOptException ex) {
            writeln("ERROR: " ~ ex.msg);
            return;
        }
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

        DirName output_dir;
        FileName main_file_hdr;
        FileName main_file_impl;
        FileName main_file_globals;        

        MainName main_name;
        MainNs main_ns;
        MainInterface main_if;

        BaseDir xml_dir;
        CompileCommandDB compile_db;
        
        FileName[] includes;
        FileData[] file_data;
    }

    static auto makeVariant(ref RawConfiguration conf) {
        auto variant = new FuzzVariant(MainFileName(conf.mainFileName), conf.xml_dir, conf.compile_db, DirName(conf.output_dir));

        return variant;
    }

    this(MainFileName main_fname, string[] xml_dir, string[] compile_db, DirName output_dir) {
        import std.path : baseName, buildPath, stripExtension;

        this.output_dir = output_dir;

        string base_filename = cast(string) main_fname;

        this.main_file_hdr = FileName(buildPath(cast(string) output_dir, base_filename ~ hdrExt));
        this.main_file_impl = FileName(buildPath(cast(string) output_dir, base_filename ~ implExt));
        this.main_file_globals = FileName(buildPath(cast(string) output_dir,
                base_filename ~ "_global" ~ implExt));

        if(xml_dir.length == 0)
            return;
        if(compile_db.length == 0)
            return;
        this.xml_dir = BaseDir(xml_dir[0]);
        this.compile_db = compile_db.fromArgCompileDb;
    }

    //Parameter functionis
    @safe string[] getIncludes() {
        import std.algorithm : map, uniq, sort;
        import std.range : array;
        import std.path : baseName;
        import std.stdio;

        return this.compile_db.getHeaderFiles.map!(a => baseName(a)).array;
    }
    
    Parameters.Files getFiles() {
        return Parameters.Files(main_file_hdr, main_file_impl,
                main_file_globals);
    }

    MainName getMainName() {
        return main_name;
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

    BaseDir getXMLBasedir() {
        return this.xml_dir;
    }

    CompileCommandDB getCompileDB() {
        return this.compile_db;
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
    import std.algorithm : canFind;

    import cpptooling.analyzer.clang.context : ClangContext;
    import cpptooling.data.representation : CppRoot;
    import dextool.compilation_db : defaultCompilerFlagFilter;
    import dextool.plugin.backend.fuzz.fuzzvariant : Generator,
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
            Generator(variant, variant).process(visitor.root, visitor.container);
            
            debug {
                logger.trace(visitor);
            }

            writeFileData(variant.file_data);
        }
    }

    return ExitStatusType.Ok;
}
