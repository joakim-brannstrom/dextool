// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module application.app_main;

import std.stdio;
import std.typecons : Flag;

import logger = std.experimental.logger;

import docopt;
import argvalue; // from docopt
import dsrcgen.cpp;

import application.types;

import cpptooling.analyzer.clang.context;
import cpptooling.analyzer.clang.visitor;
import cpptooling.data.representation : AccessType;
import cpptooling.utility.clang : visitAst, logNode;

static string main_opt = "usage:
 dextool <command> [options] [<args>...]

options:
 -h, --help         show this help
 -d, --debug        turn on debug output for tracing of generator flow
 --version          print the version of dextool

commands:
  ctestdouble       generate a C test double. Language is set to C.
  cpptestdouble     generate a C++ test double. Language is set to C++.
  help
";

static string basic_options = "
 -h, --help         show this help
 -d, --debug        turn on debug output for tracing of generator flow
 --out=dir          directory for generated files [default: ./]
 --main=name        used as part of interface, namespace etc [default: TestDouble]
 --main-fname=n     used as part of filename for generated files [default: test_double]
 --prefix=p         prefix used when generating test artifacts [default: Test_]
";

static auto ctestdouble_opt = [
    "usage:
  dextool ctestdouble [options] [--file-exclude=...] [--td-include=...] FILE [--] [CFLAGS...]
  dextool ctestdouble [options] [--file-restrict=...] [--td-include=...] FILE [--] [CFLAGS...]",
    " --strip-incl=r     A regexp used to strip the include paths
 --gmock            Generate a gmock implementation of test double interface
 --gen-pre-incl     Generate a pre include header file if it doesn't exist and use it
 --gen-post-incl    Generate a post include header file if it doesn't exist and use it",
    "
others:
 --file-exclude=     exclude files from generation matching the regex.
 --file-restrict=    restrict the scope of the test double to those files
                     matching the regex.
 --td-include=       user supplied includes used instead of those found.
"
];

static auto cpptestdouble_opt = [
    "usage:
  dextool cpptestdouble [options] [--file-exclude=...] [--td-include=...] FILE [--] [CFLAGS...]
  dextool cpptestdouble [options] [--file-restrict=...] [--td-include=...] FILE [--] [CFLAGS...]",
    " --strip-incl=r     a regexp used to strip the include paths
 --gmock            generate a gmock implementation of test double interface
 --gen-pre-incl     generate a pre include header file if it doesn't exist and use it
 --gen-post-incl    generate a post include header file if it doesn't exist and use it",
    "
others:
 --file-exclude=     exclude files from generation matching the regex.
 --file-restrict=    restrict the scope of the test double to those files
                     matching the regex.
 --td-include=       user supplied includes used instead of those found.
"
];

static string help_opt = "
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

void confLogLevel(Flag!"debug" debug_) {
    import std.exception;
    import std.experimental.logger.core : sharedLog;

    try {
        if (debug_) {
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

ExitStatusType doTestDouble(string category, string[] args) {
    import std.algorithm;
    import std.traits;

    static string optTo(string[] opt) {
        import std.format;

        auto r = format("%s

options:%s%s
%s", opt[0], basic_options, opt[1], opt[2]);

        logger.trace(r);
        return r;
    }

    auto exit_status = ExitStatusType.Errors;

    switch (category) {
    case "help":
        writeln(main_opt, help_opt);
        exit_status = ExitStatusType.Ok;
        break;
    case "ctestdouble":
        import application.ctestdouble;

        auto parsed = docopt.docopt(optTo(ctestdouble_opt), args[1 .. $]);
        printArgs(parsed);
        string[] cflags;
        if (parsed["--"].isTrue) {
            cflags = parsed["CFLAGS"].asList;
        }

        auto variant = CTestDoubleVariant.makeVariant(parsed);
        exit_status = genCstub(variant, cflags);
        break;
    case "cpptestdouble":
        import application.cpptestdouble;

        auto parsed = docopt.docopt(optTo(cpptestdouble_opt), args[1 .. $]);
        printArgs(parsed);
        string[] cflags;
        if (parsed["--"].isTrue) {
            cflags = parsed["CFLAGS"].asList;
        }

        auto variant = CppTestDoubleVariant.makeVariant(parsed);
        exit_status = genCpp(variant, cflags);
        break;
    default:
        logger.error("Usage error");
        writeln(main_opt, help_opt);
        break;
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
    import std.conv;
    import std.format : format;
    import std.string : leftJustifier;

    bool err = true;

    try {
        // dfmt off
        logger.trace("args:",
                newline,
                parsed.byKeyValue()
                    .map!(a => format("%s:%s", leftJustifier(a.key, 20), a.value.toString))
                    .joiner(newline).text()
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

auto parseMainCli(string[] args) {
    import std.algorithm;
    import std.array;
    import std.typecons;

    alias Rval = Tuple!(string, Flag!"debug", string[]);

    auto rem = args;

    auto debug_ = Flag!"debug".no;
    if (!findAmong(args, ["-d", "--debug"]).empty) {
        rem = args.filter!(a => !a.among("-d", "--debug")).array();
        debug_ = Flag!"debug".yes;
    }

    if (rem.length <= 1) {
        return Rval("help", debug_, []);
    } else if (rem.length >= 2 && args[1] == "help") {
        return Rval("help", debug_, []);
    }

    return Rval(rem[1], debug_, rem);
}

int rmain(string[] args) nothrow {
    import std.conv;
    import std.exception;

    ExitStatusType exit_status = ExitStatusType.Errors;

    try {
        auto parsed = parseMainCli(args);
        confLogLevel(parsed[1]);
        logger.trace(parsed);

        exit_status = doTestDouble(parsed[0], parsed[2]);
    }
    catch (Exception ex) {
        collectException(logger.trace(text(ex)));
        exit_status = ExitStatusType.Errors;
    }

    return cast(typeof(return)) exit_status;
}
