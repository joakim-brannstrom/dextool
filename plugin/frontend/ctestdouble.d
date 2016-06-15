// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module plugin.frontend.ctestdouble;

import logger = std.experimental.logger;

import application.types;
import application.utility;

import plugin.types;
import plugin.backend.cvariant : StubGenerator, StubController, StubParameters,
    StubProducts;
import application.compilation_db;

auto runPlugin(CliOption opt, CliArgs args) {
    import std.typecons : TypedefType;
    import docopt;
    import argvalue;

    auto parsed = docopt.docopt(cast(TypedefType!CliOption) opt, cast(TypedefType!CliArgs) args);

    string[] cflags;
    if (parsed["--"].isTrue) {
        cflags = parsed["CFLAGS"].asList;
    }

    import plugin.docopt_util;

    printArgs(parsed);

    auto variant = CTestDoubleVariant.makeVariant(parsed);

    CompileCommandDB compile_db;
    if (!parsed["--compile-db"].isEmpty) {
        compile_db = parsed["--compile-db"].asList.fromArgCompileDb;
    }

    return genCstub(variant, cflags, compile_db);
}

// dfmt off
static auto ctestdouble_opt = CliOptionParts(
    "usage:
 dextool ctestdouble [options] [--compile-db=...] [--file-exclude=...] [--td-include=...] FILE [--] [CFLAGS...]
 dextool ctestdouble [options] [--compile-db=...] [--file-restrict=...] [--td-include=...] FILE [--] [CFLAGS...]",
    // -------------
    " --out=dir          directory for generated files [default: ./]
 --main=name        Used as part of interface, namespace etc [default: TestDouble]
 --main-fname=n     Used as part of filename for generated files [default: test_double]
 --prefix=p         Prefix used when generating test artifacts [default: Test_]
 --strip-incl=r     A regexp used to strip the include paths
 --gmock            Generate a gmock implementation of test double interface
 --gen-pre-incl     Generate a pre include header file if it doesn't exist and use it
 --gen-post-incl    Generate a post include header file if it doesn't exist and use it",
    // -------------
"others:
 --compile-db=j     Retrieve compilation parameters from the file
 --file-exclude=    Exclude files from generation matching the regex.
 --file-restrict=   Restrict the scope of the test double to those files
                    matching the regex.
 --td-include=      User supplied includes used instead of those found.
"
);
// dfmt on

/** Test double generation of C code.
 *
 * TODO Describe the options.
 */
class CTestDoubleVariant : StubController, StubParameters, StubProducts {
    import std.regex : regex, Regex;
    import std.typecons : Tuple, Flag;
    import argvalue; // from docopt
    import application.types : StubPrefix, FileName, DirName;
    import application.utility;
    import dsrcgen.cpp;

    alias FileData = Tuple!(FileName, "filename", string, "data");

    static const hdrExt = ".hpp";
    static const implExt = ".cpp";

    immutable StubPrefix prefix;
    immutable StubPrefix file_prefix;

    immutable FileName input_file;
    immutable DirName output_dir;
    immutable FileName main_file_hdr;
    immutable FileName main_file_impl;
    immutable FileName main_file_globals;
    immutable FileName gmock_file;
    immutable FileName pre_incl_file;
    immutable FileName post_incl_file;

    immutable MainName main_name;
    immutable MainNs main_ns;
    immutable MainInterface main_if;
    immutable Flag!"Gmock" gmock;
    immutable Flag!"PreInclude" pre_incl;
    immutable Flag!"PostInclude" post_incl;

    Regex!char[] exclude;
    Regex!char[] restrict;

    /// Data produced by the generatore intented to be written to specified file.
    FileData[] file_data;

    private TdIncludes td_includes;

    static auto makeVariant(ref ArgValue[string] parsed) {
        import std.array : array;
        import std.algorithm : map;

        Regex!char[] exclude = parsed["--file-exclude"].asList.map!(a => regex(a)).array();
        Regex!char[] restrict = parsed["--file-restrict"].asList.map!(a => regex(a)).array();
        Regex!char strip_incl;
        Flag!"Gmock" gmock = parsed["--gmock"].isTrue ? Flag!"Gmock".yes : Flag!"Gmock".no;
        Flag!"PreInclude" pre_incl = parsed["--gen-pre-incl"].isTrue
            ? Flag!"PreInclude".yes : Flag!"PreInclude".no;
        Flag!"PostInclude" post_incl = parsed["--gen-post-incl"].isTrue
            ? Flag!"PostInclude".yes : Flag!"PostInclude".no;

        if (!parsed["--strip-incl"].isNull) {
            string strip_incl_user = parsed["--strip-incl"].toString;
            strip_incl = regex(strip_incl_user);
            logger.trace("User supplied regex via --strip-incl: ", strip_incl_user);
        } else {
            logger.trace("Using default regex to strip include path (basename)");
            strip_incl = regex(r".*/(.*)");
        }

        auto variant = new CTestDoubleVariant(StubPrefix(parsed["--prefix"].toString), StubPrefix("Not used"),
                FileName(parsed["FILE"].toString), MainFileName(parsed["--main-fname"].toString),
                MainName(parsed["--main"].toString), DirName(parsed["--out"].toString),
                gmock, pre_incl, post_incl, strip_incl);

        if (!parsed["--td-include"].isEmpty) {
            variant.forceIncludes(parsed["--td-include"].asList);
        }

        // optional parts
        variant.exclude = exclude;
        variant.restrict = restrict;

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
    this(StubPrefix prefix, StubPrefix file_prefix, FileName input_file, MainFileName main_fname, MainName main_name,
            DirName output_dir, Flag!"Gmock" gmock, Flag!"PreInclude" pre_incl,
            Flag!"PostInclude" post_incl, Regex!char strip_incl) {
        this.prefix = prefix;
        this.file_prefix = file_prefix;
        this.input_file = input_file;
        this.main_name = main_name;
        this.main_ns = MainNs(cast(string) main_name);
        this.main_if = MainInterface("I_" ~ cast(string) main_name);
        this.output_dir = output_dir;
        this.gmock = gmock;
        this.pre_incl = pre_incl;
        this.post_incl = post_incl;
        this.td_includes = TdIncludes(strip_incl);

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
    }

    /// Force the includes to be those supplied by the user.
    void forceIncludes(string[] incls) {
        td_includes.forceIncludes(incls);
    }

    /// User supplied files used as input.
    FileName getInputFile() {
        return input_file;
    }

    // -- StubController --

    bool doFile(in string filename, in string info) {
        import std.algorithm : canFind;
        import std.regex : matchFirst;

        bool r = true;

        // docopt blocks during parsing so both restrict and exclude cannot be
        // set at the same time.
        if (restrict.length > 0) {
            r = canFind!((a) {
                auto m = matchFirst(filename, a);
                return !m.empty && m.pre.length == 0 && m.post.length == 0;
            })(restrict);
            debug {
                logger.tracef(!r, "--file-restrict skipping %s", info);
            }
        } else if (exclude.length > 0) {
            r = !canFind!((a) {
                auto m = matchFirst(filename, a);
                return !m.empty && m.pre.length == 0 && m.post.length == 0;
            })(exclude);
            debug {
                logger.tracef(!r, "--file-exclude skipping %s", info);
            }
        }

        return r;
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

    // -- StubParameters --

    FileName[] getIncludes() {
        td_includes.doStrip();
        return td_includes.incls;
    }

    DirName getOutputDirectory() {
        return output_dir;
    }

    StubParameters.Files getFiles() {
        return StubParameters.Files(main_file_hdr, main_file_impl,
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
        return file_prefix;
    }

    StubPrefix getArtifactPrefix() {
        return prefix;
    }

    // -- StubProducts --

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

/// TODO refactor, doing too many things.
ExitStatusType genCstub(CTestDoubleVariant variant, string[] in_cflags, CompileCommandDB compile_db) {
    import std.conv : text;
    import std.file : exists;
    import std.path : buildNormalizedPath, asAbsolutePath;
    import std.typecons : Nullable;
    import cpptooling.analyzer.clang.context;
    import cpptooling.analyzer.clang.visitor;
    import cpptooling.data.symbol.container;
    import cpptooling.data.representation : CppRoot;

    auto cflags = prependDefaultFlags(in_cflags, "-xc");
    auto input_file = buildNormalizedPath(cast(string) variant.getInputFile).asAbsolutePath.text;
    logger.trace("Input file: ", input_file);

    if (compile_db.length > 0) {
        auto db_cflags = compile_db.appendOrError(cflags, input_file);
        if (db_cflags.isNull) {
            return ExitStatusType.Errors;
        }
        cflags = db_cflags.get;
    }

    // container not used but required when analyzing
    Container symbol_container;
    Nullable!CppRoot root;
    analyzeFile(input_file, cflags, symbol_container, root);

    if (root.isNull) {
        return ExitStatusType.Errors;
    }

    // process and put the data in variant.
    StubGenerator(variant, variant, variant).process(root.get, symbol_container);

    return writeFileData(variant.file_data);
}
