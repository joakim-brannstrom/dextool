/// Written in the D programming language.
/// Date: 2014-2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// This program is free software; you can redistribute it and/or modify
/// it under the terms of the GNU General Public License as published by
/// the Free Software Foundation; either version 2 of the License, or
/// (at your option) any later version.
///
/// This program is distributed in the hope that it will be useful,
/// but WITHOUT ANY WARRANTY; without even the implied warranty of
/// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
/// GNU General Public License for more details.
///
/// You should have received a copy of the GNU General Public License
/// along with this program; if not, write to the Free Software
/// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
module application.app_main;

import std.conv;
import std.exception;
import std.stdio;
import std.string;
import std.typecons;

import file = std.file;
import logger = std.experimental.logger;

import docopt;
import argvalue; // from docopt
import dsrcgen.cpp;

import cpptooling.analyzer.clang.context;
import cpptooling.analyzer.clang.visitor;
import cpptooling.data.representation : AccessType;
import cpptooling.utility.clang : visitAst, logNode;

import cpptooling.generator.stub.cstub : StubGenerator, StubController,
    StubParameters, StubProducts;

//TODO implement this features
// --prefix=<p>       prefix used when generating test double [default: Test_]
// --file-prefix=<p>  prefix used for generated files other than main [default: test_]

///TODO change FILE to be variable
static string doc = "
usage:
  dextool ctestdouble [options] [--file-exclude=...] [--td-include=...] FILE [--] [CFLAGS...]
  dextool ctestdouble [options] [--file-restrict=...] [--td-include=...] FILE [--] [CFLAGS...]

arguments:
 FILE           C/C++ to analyze
 CFLAGS         Compiler flags.

options:
 -h, --help         show this
 -d, --debug        turn on debug output for tracing of generator flow
 -o=dest            directory for generated files [default: ./]
 --main=name        name of the main interface and filename [default: Test_Double]
 --strip-incl=r     A regexp used to strip the include paths.

others:
 --file-exclude=...  exclude files from generation matching the regex.
 --file-restrict=... regex. restrict the scope of the test double to the set
                     union of FILE and restrict.
 --td-include=...    user supplied includes used instead of those found.

REGEX

The regex syntax is found at http://dlang.org/phobos/std_regex.html

Information about --strip-incl.
  Default regexp is: .*/(.*)

  To allow the user to selectively extract parts of the include path dextool
  applies the regex and then concatenates all the matcher groups found.  It is
  turned into the replacement include path.

  Important to remember then is that this approach requires that at least one
  matcher group exists.

EXAMPLES

Generate a simple C test double.
  dextool ctestdouble functions.h

  Analyze and generate a test double for function prototypes and extern variables.
  Both those found in functions.h and outside, aka via includes.

  The test double is written to ./test_double.hpp/.cpp.
  The name of the interface is Test_Double.

Generate a C test double excluding data from specified files.
  dextool ctestdouble --file-exclude=/foo.h --file-exclude=functions.h -o outdata/ functions.h -- -DBAR -I/some/path

  The code analyzer (Clang) will be passed the compiler flags -DBAR and -I/some/path.
  During generation declarations found in foo.h or functions.h will be excluded.

  The file holding the test double is written to directory outdata.
";

enum ExitStatusType {
    Ok,
    Errors
}

class SimpleLogger : logger.Logger {
    int line = -1;
    string file = null;
    string func = null;
    string prettyFunc = null;
    string msg = null;
    logger.LogLevel lvl;

    this(const logger.LogLevel lv = logger.LogLevel.info) {
        super(lv);
    }

    override void writeLogMsg(ref LogEntry payload) @trusted {
        this.line = payload.line;
        this.file = payload.file;
        this.func = payload.funcName;
        this.prettyFunc = payload.prettyFuncName;
        this.lvl = payload.logLevel;
        this.msg = payload.msg;

        stderr.writefln("%s: %s", text(this.lvl), this.msg);
    }
}

/** Test double generation of C code.
 *
 * TODO Describe the options.
 */
class CTestDoubleVariant : StubController, StubParameters, StubProducts {
    import std.regex : regex, Regex;
    import std.typecons : Tuple;
    import cpptooling.generator.stub.cstub : StubPrefix, FileName,
        MainInterface, DirName;

    alias FileData = Tuple!(FileName, "filename", string, "data");

    static const hdrExt = ".hpp";
    static const implExt = ".cpp";

    immutable StubPrefix prefix;
    immutable StubPrefix file_prefix;

    immutable FileName input_file;
    immutable DirName output_dir;
    immutable FileName main_file_hdr;
    immutable FileName main_file_impl;

    immutable MainInterface main_if;

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

        if (parsed["--strip-incl"].isTrue) {
            string strip_incl_user = parsed["--strip-incl"].toString;
            strip_incl = regex(strip_incl_user);
            logger.tracef("User supplied regexp %s via --strip-incl", strip_incl);
        } else {
            logger.trace("Using default regexp for stripping include path, like basename");
            strip_incl = regex(r".*/(.*)");
        }

        auto variant = new CTestDoubleVariant(StubPrefix("Not used"),
            StubPrefix("Not used"), FileName(parsed["FILE"].toString),
            MainInterface(parsed["--main"].toString), DirName(parsed["-o"].toString));

        if (!parsed["--td-include"].isEmpty) {
            variant.forceIncludes(parsed["--td-include"].asList);
        }

        variant.strip_incl = strip_incl;
        variant.exclude = exclude;
        variant.restrict = restrict;

        return variant;
    }

    this(StubPrefix prefix, StubPrefix file_prefix, FileName input_file,
        MainInterface main_if, DirName output_dir) {
        this.prefix = prefix;
        this.file_prefix = file_prefix;
        this.input_file = input_file;
        this.main_if = main_if;
        this.output_dir = output_dir;

        import std.path : baseName, buildPath, stripExtension;

        string base_filename = (cast(string) main_if).toLower;

        this.main_file_hdr = FileName(buildPath(cast(string) output_dir, base_filename ~ hdrExt));
        this.main_file_impl = FileName(buildPath(cast(string) output_dir, base_filename ~ implExt));
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

    bool doFile(in string filename) @safe {
        import std.algorithm : canFind;
        import std.regex : matchFirst;

        bool r = true;

        // docopt blocks during parsing so both restrict and exclude cannot be
        // set at the same time.
        if (restrict.length > 0) {
            r = canFind!(a => matchFirst(filename, a))(restrict);
        } else if (exclude.length > 0) {
            r = !canFind!(a => matchFirst(filename, a))(exclude);
        }

        return r;
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

    StubParameters.MainFile getMainFile() {
        return StubParameters.MainFile(main_file_hdr, main_file_impl);
    }

    MainInterface getMainInterface() {
        return main_if;
    }

    StubPrefix getFilePrefix() {
        return file_prefix;
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

///TODO don't catch Exception, catch the specific.
auto tryOpenFile(string filename, string mode) @trusted nothrow {
    import std.exception;
    import std.typecons : Unique;

    Unique!File rval;

    try {
        rval = Unique!File(new File(filename, mode));
    }
    catch (Exception ex) {
    }
    if (rval.isEmpty) {
        try {
            logger.errorf("Unable to read/write file '%s'", filename);
        }
        catch (Exception ex) {
        }
    }

    return rval;
}

///TODO don't catch Exception, catch the specific.
auto tryWriting(string fname, string data) @trusted nothrow {
    import std.exception;

    static auto action(string fname, string data) {
        auto f = tryOpenFile(fname, "w");

        if (f.isEmpty) {
            return ExitStatusType.Errors;
        }
        scope (exit)
            f.close();

        f.write(data);

        return ExitStatusType.Ok;
    }

    auto status = ExitStatusType.Errors;

    try {
        status = action(fname, data);
    }
    catch (Exception ex) {
    }

    try {
        if (status != ExitStatusType.Ok) {
            logger.error("Failed to write to file ", fname);
        }
    }
    catch (Exception ex) {
    }

    return status;
}

/// TODO refactor, too many parameters. Refactor. Probably pass the variant as a parameter.
ExitStatusType genCstub(CTestDoubleVariant variant, string[] in_cflags) {
    import std.exception;
    import std.path : baseName, buildPath, stripExtension;
    import std.file : exists;
    import cpptooling.analyzer.clang.context;
    import cpptooling.analyzer.clang.visitor;

    ///TODO move to clang module.
    static auto prependLangFlagIfMissing(string[] in_cflags) {
        import std.algorithm : among;

        if (!["-xc", "-xc++"].among(in_cflags)) {
            return ["-xc"] ~ in_cflags;
        }

        return in_cflags.dup;
    }

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

void prepareEnv(ref ArgValue[string] parsed) {
    import std.experimental.logger.core : sharedLog;

    try {
        if (parsed["--debug"].isTrue) {
            logger.globalLogLevel(logger.LogLevel.all);
        } else {
            logger.globalLogLevel(logger.LogLevel.info);
            auto simple_logger = new SimpleLogger();
            logger.sharedLog(simple_logger);
        }
    }
    catch (Exception ex) {
        collectException(logger.error("Failed to configure logging level"));
        throw ex;
    }
}

ExitStatusType doTestDouble(ref ArgValue[string] parsed) {
    import std.algorithm : among;

    ExitStatusType exit_status = ExitStatusType.Errors;

    string[] cflags;
    if (parsed["--"].isTrue) {
        cflags = parsed["CFLAGS"].asList;
    }

    if (parsed["ctestdouble"].isTrue) {
        auto variant = CTestDoubleVariant.makeVariant(parsed);
        exit_status = genCstub(variant, cflags);
    } else {
        logger.error("Usage error");
        writeln(doc);
    }

    return exit_status;
}

int rmain(string[] args) nothrow {
    import std.array : join;

    string errmsg, tracemsg;
    ExitStatusType exit_status = ExitStatusType.Errors;
    bool help = true;
    bool optionsFirst = false;
    auto version_ = "gen-test-double v0.1";

    try {
        auto parsed = docopt.docopt(doc, args[1 .. $], help, version_, optionsFirst);
        prepareEnv(parsed);
        logger.trace(to!string(args));
        logger.trace(join(args, " "));
        logger.trace(prettyPrintArgs(parsed));

        exit_status = doTestDouble(parsed);
    }
    catch (Exception ex) {
        collectException(logger.trace(text(ex)));
        exit_status = ExitStatusType.Errors;
    }

    return cast(typeof(return)) exit_status;
}
