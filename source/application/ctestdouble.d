// Written in the D programming language.
/**
Date: 2015, Joakim Brännström
License: GPL
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*/
module application.ctestdouble;

import logger = std.experimental.logger;

import application.types;
import application.utility;

import cpptooling.generator.stub.cstub : StubGenerator, StubController,
    StubParameters, StubProducts;

/** Test double generation of C code.
 *
 * TODO Describe the options.
 */
class CTestDoubleVariant : StubController, StubParameters, StubProducts {
    import std.string : toLower;
    import std.regex : regex, Regex;
    import std.typecons : Tuple, Flag;
    import argvalue; // from docopt
    import cpptooling.generator.stub.cstub : StubPrefix, FileName,
        MainInterface, DirName;
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

    immutable MainInterface main_if;
    immutable Flag!"Gmock" gmock;
    immutable Flag!"PreInclude" pre_incl;
    immutable Flag!"PostInclude" post_incl;

    Regex!char[] exclude;
    Regex!char[] restrict;
    Regex!char strip_incl;

    /// Data produced by the generatore intented to be written to specified file.
    FileData[] file_data;

    /// Includes intended for the test double. Filtered according to the user.
    private FileName[] td_includes;
    // Dirty flag so sorting is only done when needed.
    enum IncludeState {
        Dirty,
        Clean,
        UserDefined
    }

    private IncludeState td_includes_st;

    static auto makeVariant(ref ArgValue[string] parsed) {
        import std.array : array;
        import std.algorithm : map;

        Regex!char[] exclude = parsed["--file-exclude"].asList.map!(a => regex(a)).array();
        Regex!char[] restrict = parsed["--file-restrict"].asList.map!(a => regex(a)).array();
        Regex!char strip_incl;
        Flag!"Gmock" gmock = parsed["--gmock"].isTrue ? Flag!"Gmock".yes : Flag!"Gmock".no;
        Flag!"PreInclude" pre_incl = parsed["--gen-pre-incl"].isTrue ? Flag!"PreInclude".yes
            : Flag!"PreInclude".no;
        Flag!"PostInclude" post_incl = parsed["--gen-post-incl"].isTrue ? Flag!"PostInclude".yes
            : Flag!"PostInclude".no;

        if (parsed["--strip-incl"].isTrue) {
            string strip_incl_user = parsed["--strip-incl"].toString;
            strip_incl = regex(strip_incl_user);
            logger.tracef("User supplied regexp %s via --strip-incl", strip_incl);
        } else {
            logger.trace("Using default regexp for stripping include path (basename)");
            strip_incl = regex(r".*/(.*)");
        }

        auto variant = new CTestDoubleVariant(StubPrefix(parsed["--prefix"].toString),
            StubPrefix("Not used"), FileName(parsed["FILE"].toString),
            MainInterface(parsed["--main"].toString),
            DirName(parsed["--out"].toString), gmock, pre_incl, post_incl);

        if (!parsed["--td-include"].isEmpty) {
            variant.forceIncludes(parsed["--td-include"].asList);
        }

        variant.strip_incl = strip_incl;
        variant.exclude = exclude;
        variant.restrict = restrict;

        return variant;
    }

    this(StubPrefix prefix, StubPrefix file_prefix, FileName input_file,
        MainInterface main_if, DirName output_dir, Flag!"Gmock" gmock,
        Flag!"PreInclude" pre_incl, Flag!"PostInclude" post_incl) {
        this.prefix = prefix;
        this.file_prefix = file_prefix;
        this.input_file = input_file;
        this.main_if = main_if;
        this.output_dir = output_dir;
        this.gmock = gmock;
        this.pre_incl = pre_incl;
        this.post_incl = post_incl;

        import std.path : baseName, buildPath, stripExtension;

        string base_filename = (cast(string) main_if).toLower;

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
        foreach (incl; incls) {
            td_includes ~= FileName(incl);
        }
        td_includes_st = IncludeState.UserDefined;
    }

    /// User supplied files used as input.
    FileName getInputFile() {
        return input_file;
    }

    // -- StubController --

    bool doFile(in string filename) {
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
        } else if (exclude.length > 0) {
            r = !canFind!((a) {
                auto m = matchFirst(filename, a);
                return !m.empty && m.pre.length == 0 && m.post.length == 0;
            })(exclude);
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
        import std.array : array;
        import std.algorithm : cache, map, filter;
        import cpptooling.data.representation : dedup;

        // if no regexp or no match when using the regexp, using the include
        // path as-is.
        @property static auto stripIncl(FileName incl, Regex!char re) @trusted {
            import std.algorithm : joiner;
            import std.range : dropOne;
            import std.regex : matchFirst;
            import std.utf : byChar;

            auto c = matchFirst(cast(string) incl, re);
            auto rval = incl;
            logger.tracef("for input '%s', --strip-incl match is: %s", cast(string) incl,
                c);
            if (!c.empty) {
                rval = FileName(cast(string) c.dropOne.joiner("").byChar.array());
            }

            return rval;
        }

        final switch (td_includes_st) {
        case IncludeState.Dirty:
            // dfmt off
            td_includes = dedup(td_includes)
                .map!(a => stripIncl(a, strip_incl))
                .cache()
                .filter!(a => a.length > 0)
                .array();
            // dfmt on
            td_includes_st = IncludeState.Clean;
            break;

        case IncludeState.Clean:
            break;
        case IncludeState.UserDefined:
            break;
        }

        return td_includes;
    }

    DirName getOutputDirectory() {
        return output_dir;
    }

    StubParameters.Files getFiles() {
        return StubParameters.Files(main_file_hdr, main_file_impl,
            main_file_globals, gmock_file, pre_incl_file, post_incl_file);
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

    void putLocation(FileName fname) {
        final switch (td_includes_st) {
        case IncludeState.Dirty:
            td_includes ~= fname;
            break;
        case IncludeState.Clean:
            td_includes ~= fname;
            td_includes_st = IncludeState.Dirty;
            break;
        case IncludeState.UserDefined:
            break;
        }
    }
}

/// TODO refactor, doing too many things.
ExitStatusType genCstub(CTestDoubleVariant variant, string[] in_cflags) {
    import std.exception;
    import std.path : baseName, buildPath, stripExtension;
    import std.file : exists;
    import cpptooling.analyzer.clang.context;
    import cpptooling.analyzer.clang.visitor;

    if (!exists(cast(string) variant.getInputFile)) {
        logger.errorf("File '%s' do not exist", cast(string) variant.getInputFile);
        return ExitStatusType.Errors;
    }

    auto cflags = prependLangFlagIfMissing(in_cflags);

    auto file_ctx = ClangContext(cast(string) variant.getInputFile, cflags);
    logDiagnostic(file_ctx);
    if (file_ctx.hasParseErrors)
        return ExitStatusType.Errors;

    auto ctx = ParseContext();
    ctx.visit(file_ctx.cursor);

    // process and put the data in variant.
    StubGenerator(variant, variant, variant).process(ctx.root);

    foreach (p; variant.file_data) {
        auto status = tryWriting(cast(string) p.filename, p.data);
        if (status != ExitStatusType.Ok) {
            return ExitStatusType.Errors;
        }
    }

    return ExitStatusType.Ok;
}
