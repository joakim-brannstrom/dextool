/**
Copyright: Copyright (c) 2015-2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module plugin.frontend.ctestdouble;

import logger = std.experimental.logger;

import application.compilation_db;
import application.types;
import application.utility;

import plugin.types;
import plugin.backend.ctestdouble.cvariant : Controller, Parameters, Products;

struct ParsedArgs {
    string[] fileExclude;
    string[] fileRestrict;
    string[] testDoubleInclude;
    string[] inFiles;
    string[] cflags;
    string[] compileDb;
    string header;
    string headerFile;
    string mainName = "TestDouble";
    string mainFileName = "test_double";
    string prefix = "Test_";
    string stripInclude;
    string out_;
    bool help;
    bool gmock;
    bool generatePreInclude;
    bool genPostInclude;
    bool locationAsComment;
    bool generateZeroGlobals;

    string[] originalFlags;

    void parse(string[] args) {
        import std.getopt;

        originalFlags = args.dup;

        try {
            bool no_zero_globals;
            // dfmt off
            getopt(args, std.getopt.config.keepEndOfOptions, "h|help", &help,
                   "main", &mainName,
                   "main-fname", &mainFileName,
                   "out", &out_,
                   "compile-db", &compileDb,
                   "no-zeroglobals", &no_zero_globals,
                   "prefix", &prefix,
                   "strip-incl", &stripInclude,
                   "header", &header,
                   "header-file", &headerFile,
                   "gmock", &gmock,
                   "gen-pre-incl", &generatePreInclude,
                   "gen-post-incl", &genPostInclude,
                   "loc-as-comment", &locationAsComment,
                   "td-include", &testDoubleInclude,
                   "file-exclude", &fileExclude,
                   "file-restrict", &fileRestrict,
                   "in", &inFiles);
            // dfmt on
            generateZeroGlobals = !no_zero_globals;
        }
        catch (std.getopt.GetOptException ex) {
            logger.error(ex.msg);
            help = true;
        }

        import std.algorithm : find;
        import std.array : array;
        import std.range : drop;

        // at this point args contain "what is left". What is interesting then is those after "--".
        cflags = args.find("--").drop(1).array();
    }

    void printHelp() {
        import std.stdio : writefln;

        writefln("%s\n\n%s\n%s", ctestdouble_opt.usage,
                ctestdouble_opt.optional, ctestdouble_opt.others);
    }

    void dump() {
        logger.tracef("args:
--header            :%s
--header-file       :%s
--file-restrict     :%s
--prefix            :%s
--gmock             :%s
--out               :%s
--file-exclude      :%s
--main              :%s
--strip-incl        :%s
--main-fname        :%s
--in                :%s
--compile-db        :%s
--gen-post-incl     :%s
--gen-pre-incl      :%s
--help              :%s
--loc-as-comment    :%s
--td-include        :%s
CFLAGS              :%s", header, headerFile, fileRestrict, prefix, gmock,
                out_, fileExclude, mainName, stripInclude,
                mainFileName, inFiles, compileDb, genPostInclude, generatePreInclude,
                help, locationAsComment, testDoubleInclude, cflags);
    }
}

auto runPlugin(CliBasicOption opt, CliArgs args) {
    import std.array : appender;
    import std.stdio : writeln;

    ParsedArgs pargs;
    pargs.parse(args);
    pargs.dump;

    if (pargs.help) {
        pargs.printHelp;
        return ExitStatusType.Ok;
    } else if (pargs.inFiles.length == 0) {
        writeln("Missing required argument --in");
        return ExitStatusType.Errors;
    } else if (pargs.fileExclude.length != 0 && pargs.fileRestrict.length != 0) {
        writeln("Unable to combine both --file-exclude and --file-restrict");
        return ExitStatusType.Errors;
    }

    auto variant = CTestDoubleVariant.makeVariant(pargs);
    auto app = appender!string();
    variant.putFile(variant.getXmlConfigFile, makeXmlConnfig(app, pargs.originalFlags).data);

    CompileCommandDB compile_db;
    if (pargs.compileDb.length != 0) {
        compile_db = pargs.compileDb.fromArgCompileDb;
    }

    return genCstub(variant, pargs.cflags, compile_db, InFiles(pargs.inFiles));
}

// dfmt off
static auto ctestdouble_opt = CliOptionParts(
    "usage:
 dextool ctestdouble [options] [--compile-db=...] [--file-exclude=...] [--td-include=...] --in=... [--] [CFLAGS...]
 dextool ctestdouble [options] [--compile-db=...] [--file-restrict=...] [--td-include=...] --in=... [--] [CFLAGS...]",
    // -------------
    "--main=name        Used as part of interface, namespace etc [default: TestDouble]
 --main-fname=n     Used as part of filename for generated files [default: test_double]
 --prefix=p         Prefix used when generating test artifacts [default: Test_]
 --strip-incl=r     A regexp used to strip the include paths
 --gmock            Generate a gmock implementation of test double interface
 --gen-pre-incl     Generate a pre include header file if it doesn't exist and use it
 --gen-post-incl    Generate a post include header file if it doesn't exist and use it
 --loc-as-comment   Generate a comment containing the location the symbol was derived from.
                    Makes it easier to correctly define excludes/restricts
 --header=s         Prepend generated files with the string
 --header-file=f    Prepend generated files with the header read from the file
 --no-zeroglobals   Turn off generation of the default implementation that zeroes globals",
    // -------------
"others:
 --in=              Input files to parse
 --out=dir          directory for generated files [default: ./]
 --compile-db=      Retrieve compilation parameters from the file
 --file-exclude=    Exclude files from generation matching the regex
 --file-restrict=   Restrict the scope of the test double to those files
                    matching the regex
 --td-include=      User supplied includes used instead of those found

REGEX
The regex syntax is found at http://dlang.org/phobos/std_regex.html

Information about --strip-incl.
  Default regexp is: .*/(.*)

  To allow the user to selectively extract parts of the include path dextool
  applies the regex and then concatenates all the matcher groups found.  It is
  turned into the replacement include path.

  Important to remember then is that this approach requires that at least one
  matcher group exists.

Information about --file-exclude.
  The regex must fully match the filename the AST node is located in.
  If it matches all data from the file is excluded from the generated code.

Information about --file-restrict.
  The regex must fully match the filename the AST node is located in.
  Only symbols from files matching the restrict affect the generated test double.

EXAMPLES

Generate a simple C test double.
  dextool ctestdouble functions.h

  Analyze and generate a test double for function prototypes and extern variables.
  Both those found in functions.h and outside, aka via includes.

  The test double is written to ./test_double.hpp/.cpp.
  The name of the interface is Test_Double.

Generate a C test double excluding data from specified files.
  dextool ctestdouble --file-exclude=/foo.h --file-exclude='functions.[h,c]' --out=outdata/ functions.h -- -DBAR -I/some/path

  The code analyzer (Clang) will be passed the compiler flags -DBAR and -I/some/path.
  During generation declarations found in foo.h or functions.h will be excluded.

  The file holding the test double is written to directory outdata.
"
);
// dfmt on

struct FileData {
    import application.types : FileName;

    FileName filename;
    string data;
}

/** Test double generation of C code.
 *
 * TODO Describe the options.
 */
class CTestDoubleVariant : Controller, Parameters, Products {
    import std.regex : regex, Regex;
    import std.typecons : Flag;
    import application.types : StubPrefix, FileName, DirName;
    import cpptooling.testdouble.header_filter : TestDoubleIncludes,
        LocationType;
    import dsrcgen.cpp : CppModule, CppHModule;

    private {
        static const hdrExt = ".hpp";
        static const implExt = ".cpp";
        static const xmlExt = ".xml";

        StubPrefix prefix;

        DirName output_dir;
        FileName main_file_hdr;
        FileName main_file_impl;
        FileName main_file_globals;
        FileName gmock_file;
        FileName pre_incl_file;
        FileName post_incl_file;
        FileName log_file;
        CustomHeader custom_hdr;

        MainName main_name;
        MainNs main_ns;
        MainInterface main_if;
        Flag!"Gmock" gmock;
        Flag!"PreInclude" pre_incl;
        Flag!"PostInclude" post_incl;
        Flag!"locationAsComment" loc_as_comment;
        Flag!"generateZeroGlobals" generate_zero_globals;

        Regex!char[] exclude;
        Regex!char[] restrict;

        /// Data produced by the generatore intented to be written to specified file.
        FileData[] file_data;

        TestDoubleIncludes td_includes;
    }

    static auto makeVariant(ref ParsedArgs args) {
        Regex!char strip_incl;
        CustomHeader custom_hdr;

        if (args.stripInclude.length != 0) {
            strip_incl = regex(args.stripInclude);
            logger.trace("User supplied regex via --strip-incl: ", args.stripInclude);
        } else {
            logger.trace("Using default regex to strip include path (basename)");
            strip_incl = regex(r".*/(.*)");
        }

        // dfmt off
        auto variant = new CTestDoubleVariant(
                MainFileName(args.mainFileName), DirName(args.out_),
                strip_incl)
            .argPrefix(args.prefix)
            .argMainName(args.mainName)
            .argLocationAsComment(args.locationAsComment)
            .argGmock(args.gmock)
            .argPreInclude(args.generatePreInclude)
            .argPostInclude(args.genPostInclude)
            .argForceTestDoubleIncludes(args.testDoubleInclude)
            .argFileExclude(args.fileExclude)
            .argFileRestrict(args.fileRestrict)
            .argCustomHeader(args.header, args.headerFile)
            .argGenerateZeroGlobals(args.generateZeroGlobals);
        // dfmt on

        return variant;
    }

    /** Design of c'tor.
     *
     * The c'tor has as paramters all the required configuration data.
     * Assignment of members are used for optional configuration.
     *
     * Follows the design pattern "correct by construction".
     *
     * TODO document the parameters.
     */
    this(MainFileName main_fname, DirName output_dir, Regex!char strip_incl) {
        this.output_dir = output_dir;
        this.td_includes = TestDoubleIncludes(strip_incl);

        import std.path : baseName, buildPath, stripExtension;

        string base_filename = cast(string) main_fname;

        this.main_file_hdr = FileName(buildPath(cast(string) output_dir, base_filename ~ hdrExt));
        this.main_file_impl = FileName(buildPath(cast(string) output_dir, base_filename ~ implExt));
        this.main_file_globals = FileName(buildPath(cast(string) output_dir,
                base_filename ~ "_global" ~ implExt));
        this.gmock_file = FileName(buildPath(cast(string) output_dir,
                base_filename ~ "_gmock" ~ hdrExt));
        this.pre_incl_file = FileName(buildPath(cast(string) output_dir,
                base_filename ~ "_pre_includes" ~ hdrExt));
        this.post_incl_file = FileName(buildPath(cast(string) output_dir,
                base_filename ~ "_post_includes" ~ hdrExt));
        this.log_file = FileName(buildPath(output_dir, base_filename ~ xmlExt));
    }

    auto argFileExclude(string[] a) {
        import std.array : array;
        import std.algorithm : map;

        this.exclude = a.map!(a => regex(a)).array();
        return this;
    }

    auto argFileRestrict(string[] a) {
        import std.array : array;
        import std.algorithm : map;

        this.restrict = a.map!(a => regex(a)).array();
        return this;
    }

    auto argPrefix(string s) {
        this.prefix = StubPrefix(s);
        return this;
    }

    auto argMainName(string s) {
        this.main_name = MainName(s);
        this.main_ns = MainNs(s);
        this.main_if = MainInterface("I_" ~ s);
        return this;
    }

    /// Force the includes to be those supplied by the user.
    auto argForceTestDoubleIncludes(string[] a) {
        if (a.length != 0) {
            td_includes.forceIncludes(a);
        }
        return this;
    }

    auto argCustomHeader(string header, string header_file) {
        if (header.length != 0) {
            this.custom_hdr = CustomHeader(header);
        } else if (header_file.length != 0) {
            import std.file : readText;

            string content = readText(header_file);
            this.custom_hdr = CustomHeader(content);
        }

        return this;
    }

    auto argGmock(bool a) {
        this.gmock = cast(Flag!"Gmock") a;
        return this;
    }

    auto argPreInclude(bool a) {
        this.pre_incl = cast(Flag!"PreInclude") a;
        return this;
    }

    auto argPostInclude(bool a) {
        this.post_incl = cast(Flag!"PostInclude") a;
        return this;
    }

    auto argLocationAsComment(bool a) {
        this.loc_as_comment = cast(Flag!"locationAsComment") a;
        return this;
    }

    auto argGenerateZeroGlobals(bool value) {
        this.generate_zero_globals = cast(Flag!"generateZeroGlobals") value;
        return this;
    }

    void processIncludes() {
        td_includes.process();
    }

    void finalizeIncludes() {
        td_includes.finalize();
    }

    /// Make an .ini-file containing the configuration data.
    FileName getXmlConfigFile() {
        return log_file;
    }

    /// Data produced by the generatore intented to be written to specified file.
    ref FileData[] getProducedFiles() {
        return file_data;
    }

    // -- Controller --

    bool doFile(in string filename, in string info) {
        import std.algorithm : canFind;
        import std.regex : matchFirst;

        bool decision = true;

        // blocks during arg parsing so both restrict and exclude cannot be set
        // at the same time.
        if (restrict.length > 0) {
            decision = canFind!((a) {
                auto m = matchFirst(filename, a);
                return !m.empty && m.pre.length == 0 && m.post.length == 0;
            })(restrict);
            debug {
                logger.tracef(!decision, "--file-restrict skipping %s", info);
            }
        } else if (exclude.length > 0) {
            decision = !canFind!((a) {
                auto m = matchFirst(filename, a);
                return !m.empty && m.pre.length == 0 && m.post.length == 0;
            })(exclude);
            debug {
                logger.tracef(!decision, "--file-exclude skipping %s", info);
            }
        }

        return decision;
    }

    bool doGoogleMock() {
        return gmock;
    }

    bool doPreIncludes() {
        import std.path : exists;

        return pre_incl && !exists(cast(string) pre_incl_file);
    }

    bool doIncludeOfPreIncludes() {
        return pre_incl;
    }

    bool doPostIncludes() {
        import std.path : exists;

        return post_incl && !exists(cast(string) post_incl_file);
    }

    bool doIncludeOfPostIncludes() {
        return post_incl;
    }

    bool doLocationAsComment() {
        return loc_as_comment;
    }

    // -- Parameters --

    FileName[] getIncludes() {
        import std.algorithm : map;
        import std.array : array;

        return td_includes.includes.map!(a => FileName(a)).array();
    }

    DirName getOutputDirectory() {
        return output_dir;
    }

    Parameters.Files getFiles() {
        return Parameters.Files(main_file_hdr, main_file_impl,
                main_file_globals, gmock_file, pre_incl_file, post_incl_file);
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

    StubPrefix getFilePrefix() {
        return StubPrefix("");
    }

    StubPrefix getArtifactPrefix() {
        return prefix;
    }

    DextoolVersion getToolVersion() {
        import application.utility : dextoolVersion;

        return dextoolVersion;
    }

    CustomHeader getCustomHeader() {
        return custom_hdr;
    }

    Flag!"generateZeroGlobals" generateZeroGlobals() {
        return generate_zero_globals;
    }

    // -- Products --

    void putFile(FileName fname, string data) {
        file_data ~= FileData(fname, data);
    }

    void putFile(FileName fname, CppHModule hdr_data) {
        file_data ~= FileData(fname, hdr_data.render());
    }

    void putFile(FileName fname, CppModule impl_data) {
        file_data ~= FileData(fname, impl_data.render());
    }

    void putLocation(FileName fname, LocationType type) {
        td_includes.put(fname, type);
    }
}

/** Store the input in a configuration file to make it easy to regenerate the
 * test double.
 */
ref AppT makeXmlConnfig(AppT)(ref AppT app, string[] flags) {
    import std.algorithm : joiner;
    import std.array : array;
    import std.file : thisExePath;
    import std.format : formattedWrite, format;
    import std.path : baseName;
    import std.range : put;
    import std.utf : toUTF8;
    import std.xml;
    import application.utility : dextoolVersion;

    auto doc = new Document(new Tag("dextool"));
    doc.tag.attr["version"] = dextoolVersion;
    {
        auto command = new Element("command");
        command ~= new CData(format("%s %s", thisExePath.baseName,
                flags.joiner(" ").array().toUTF8));
        doc ~= new Comment("command line when dextool was executed");
        doc ~= command;
    }

    formattedWrite(app, `<?xml version="1.0" encoding="UTF-8"?>` ~ "\n");
    put(app, doc.pretty(4).joiner("\n").array().toUTF8());

    return app;
}

/// TODO refactor, doing too many things.
ExitStatusType genCstub(CTestDoubleVariant variant, in string[] in_cflags,
        CompileCommandDB compile_db, InFiles in_files) {
    import std.conv : text;
    import std.path : buildNormalizedPath, asAbsolutePath;
    import std.typecons : Yes;

    import cpptooling.analyzer.clang.context : ClangContext;
    import plugin.backend.ctestdouble.cvariant : CVisitor, Generator;

    const auto user_cflags = prependDefaultFlags(in_cflags, "-xc");
    const auto total_files = in_files.length;
    auto visitor = new CVisitor(variant, variant);
    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    auto generator = Generator(variant, variant, variant);

    foreach (idx, in_file; in_files) {
        logger.infof("File %d/%d ", idx + 1, total_files);
        string[] use_cflags;
        string abs_in_file;

        // TODO duplicate code in c, c++ and plantuml. Fix it.
        if (compile_db.length > 0) {
            auto db_search_result = compile_db.appendOrError(user_cflags, in_file);
            if (db_search_result.isNull) {
                return ExitStatusType.Errors;
            }
            use_cflags = db_search_result.get.cflags;
            abs_in_file = db_search_result.get.absoluteFile;
        } else {
            use_cflags = user_cflags.dup;
            abs_in_file = buildNormalizedPath(in_file).asAbsolutePath.text;
        }

        if (analyzeFile(abs_in_file, use_cflags, visitor, ctx) == ExitStatusType.Errors) {
            return ExitStatusType.Errors;
        }

        generator.aggregate(visitor.root, visitor.container);
        visitor.clearRoot;
        variant.processIncludes;
    }

    variant.finalizeIncludes;

    // Analyse and generate test double
    generator.process(visitor.container);

    debug {
        logger.trace(visitor);
    }

    return writeFileData(variant.getProducedFiles);
}
