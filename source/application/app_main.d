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

///TODO change FILE to be variable
static string doc = "
usage:
  dextool ctestdouble [options] [--exclude=...] FILE [--] [CFLAGS...]

arguments:
 FILE           C/C++ to analyze
 CFLAGS         Compiler flags.

options:
 -h, --help         show this
 -o=<dest>          destination of generated files [default: .]
 -d, --debug        turn on debug output for tracing of generator flow

others:
 --exclude=...      exclude files from generation, repeatable.

example:

Generate a C test double.
  dextool ctestdouble --exclude=/foo.h --exclude=functions.h -o outdata/ functions.h -- -DBAR -I/some/path

  Analyze and generate a test double for function prototypes and extern variables.
  The code analyzer (Clang) will be passed the compiler flags -DBAR and -I/some/path.
  During generation declarations found in foo.h or functions.h will be excluded.
  The generated test double is written to the directory outdata.
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
    import std.typecons : Tuple;
    import cpptooling.generator.stub.cstub : StubPrefix, FileName;

    alias FileData = Tuple!(FileName, "filename", string, "data");

    static const hdrExt = ".hpp";
    static const implExt = ".cpp";

    immutable StubPrefix prefix;
    immutable FileName inputFile;
    immutable FileName hdrOutputFile;
    immutable FileName implIncludeFile;
    immutable FileName implOutputFile;

    FileData[] fileData;

    ///TODO change from string to typed parameters.
    this(string prefix, string input_file, string output_dir) {
        this.prefix = StubPrefix(prefix);

        import std.path : baseName, buildPath, stripExtension;

        auto base_filename = input_file.baseName.stripExtension;

        inputFile = FileName(input_file.baseName);
        implIncludeFile = FileName((cast(string) prefix).toLower ~ "_" ~ base_filename ~ hdrExt);

        hdrOutputFile = FileName(buildPath(output_dir, cast(string) implIncludeFile));
        implOutputFile = FileName(buildPath(output_dir,
            (cast(string) prefix).toLower ~ "_" ~ base_filename ~ implExt));
    }

    // -- StubController --

    bool doFile(in string filename) @safe {
        return true;
    }

    // -- StubParameters --

    FileName getInputFile() @safe pure {
        return inputFile;
    }

    FileName getImplementationIncludeFile() @safe pure {
        return implIncludeFile;
    }

    FileName getOutputHdr() @safe pure {
        return hdrOutputFile;
    }

    FileName getOutputImpl() @safe pure {
        return implOutputFile;
    }

    StubPrefix getFilePrefix() @safe pure {
        return prefix;
    }

    StubPrefix getManagerPrefix() @safe pure {
        return prefix;
    }

    // -- StubProducts --

    void putFile(FileName fname, CppHModule hdr_data) {
        fileData ~= FileData(fname, hdr_data.render());
    }

    void putFile(FileName fname, CppModule impl_data) {
        fileData ~= FileData(fname, impl_data.render());
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

ExitStatusType genCstub(string infile, string outdir, string[] in_cflags) {
    import std.exception;
    import std.path : baseName, buildPath, stripExtension;
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

    auto cflags = prependLangFlagIfMissing(in_cflags);

    if (!file.exists(infile)) {
        logger.errorf("File '%s' do not exist", infile);
        return ExitStatusType.Errors;
    }

    logger.infof("Generating stub from '%s'", infile);
    auto variant = new CTestDoubleVariant("Stub", infile, outdir);

    auto file_ctx = ClangContext(infile, cflags);
    logDiagnostic(file_ctx);
    if (file_ctx.hasParseErrors)
        return ExitStatusType.Errors;

    auto ctx = ParseContext();
    ctx.visit(file_ctx.cursor);

    // process and put the data in variant.
    StubGenerator(variant, variant, variant).process(ctx.root);

    foreach (p; variant.fileData) {
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
        exit_status = genCstub(parsed["FILE"].toString, parsed["-o"].toString, cflags);
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
