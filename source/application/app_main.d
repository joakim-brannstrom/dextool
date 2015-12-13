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

import std.stdio;

import logger = std.experimental.logger;

import docopt;
import argvalue; // from docopt
import dsrcgen.cpp;

import application.types;

import cpptooling.analyzer.clang.context;
import cpptooling.analyzer.clang.visitor;
import cpptooling.data.representation : AccessType;
import cpptooling.utility.clang : visitAst, logNode;

static string doc = "
usage:
  dextool ctestdouble [options] [--file-exclude=...] [--td-include=...] FILE [--] [CFLAGS...]
  dextool ctestdouble [options] [--file-restrict=...] [--td-include=...] FILE [--] [CFLAGS...]
  dextool cpptestdouble [options] [--file-exclude=...] [--td-include=...] FILE [--] [CFLAGS...]
  dextool cpptestdouble [options] [--file-restrict=...] [--td-include=...] FILE [--] [CFLAGS...]

arguments:
 FILE           C/C++ to analyze
 CFLAGS         Compiler flags.

options:
 -h, --help         show this help
 -d, --debug        turn on debug output for tracing of generator flow
 --out=dir          directory for generated files [default: ./]
 --main=name        used as part of interface, namespace etc [default: TestDouble]
 --main-fname=n     used as part of filename for generated files [default: test_double]
 --prefix=p         prefix used when generating test artifacts [default: Test_]
 --strip-incl=r     A regexp used to strip the include paths
 --gmock            Generate a gmock implementation of test double interface
 --gen-pre-incl     Generate a pre include header file if it doesn't exist and use it
 --gen-post-incl    Generate a post include header file if it doesn't exist and use it

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
  dextool ctestdouble --file-exclude=/foo.h --file-exclude=functions.[h,c] --out=outdata/ functions.h -- -DBAR -I/some/path

  The code analyzer (Clang) will be passed the compiler flags -DBAR and -I/some/path.
  During generation declarations found in foo.h or functions.h will be excluded.

  The file holding the test double is written to directory outdata.
";

class SimpleLogger : logger.Logger {
    import std.conv;

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

void prepareEnv(ref ArgValue[string] parsed) {
    import std.exception;
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
        import application.ctestdouble;

        auto variant = CTestDoubleVariant.makeVariant(parsed);
        exit_status = genCstub(variant, cflags);
    } else if (parsed["cpptestdouble"].isTrue) {
        import application.cpptestdouble;

        auto variant = CppTestDoubleVariant.makeVariant(parsed);
        exit_status = genCpp(variant, cflags);
    } else {
        logger.error("Usage error");
        writeln(doc);
    }

    return exit_status;
}

/** Correctly log all type of messages via logger.
 *
 * docopt uses std.json internally for pretty printing which results in errors
 * for regex containing things like "\.".
 */
void printArgs(ref ArgValue[string] parsed) nothrow {
    import std.algorithm : map, joiner;
    import std.ascii : newline;
    import std.format : format;
    import std.stdio : writeln;
    import std.string : leftJustifier;

    bool err = true;

    try {
        // dfmt off
        writeln("args:",
                newline,
                parsed.byKeyValue()
                    .map!(a => format("%s:%s", leftJustifier(a.key, 20), a.value.toString))
                    .joiner(newline)
               );
        // dfmt on
        err = false;
    }
    catch (Exception ex) {
        ///TODO change to the specific exceptions.
    }

    if (err) {
        try {
            logger.error("Unable to log parsed program arguments");
        }
        catch (Exception ex) {
        }
    }
}

int rmain(string[] args) nothrow {
    import std.conv;
    import std.exception;

    string errmsg, tracemsg;
    ExitStatusType exit_status = ExitStatusType.Errors;
    bool help = true;
    bool optionsFirst = false;
    auto version_ = "dextool v0.4.1";

    try {
        auto parsed = docopt.docopt(doc, args[1 .. $], help, version_, optionsFirst);
        prepareEnv(parsed);
        printArgs(parsed);

        exit_status = doTestDouble(parsed);
    }
    catch (Exception ex) {
        collectException(logger.trace(text(ex)));
        exit_status = ExitStatusType.Errors;
    }

    return cast(typeof(return)) exit_status;
}
