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

string cliMergeCategory() {
    import std.algorithm : map, joiner, reduce, max;
    import std.ascii : newline;
    import std.conv : text;
    import std.range : chain, only;
    import std.string : leftJustifier;

    import plugin.register;

    // dfmt off
    auto max_length = getRegisteredPlugins()
        .map!(a => a.category.length)
        .reduce!((a,b) => max(a,b));

    return getRegisteredPlugins()
        .map!(a =>
              chain(only("  "),
                    // +1 so there is a space left between category and info
                    only(leftJustifier(cast(string) a.category, max_length + 1).text),
                    only(cast(string) a.categoryCliInfo))
              .joiner()
             )
        .joiner(newline)
        .text();
    // dfmt on
}

ExitStatusType doTestDouble(string category, string[] args) {
    import std.algorithm;
    import std.traits;

    // load the plugin system
    import plugin.loader;
    import plugin.types;

    static auto optTo(CliOptionParts opt) {
        import std.format;

        auto r = format("%s

options:%s%s

%s", opt.usage, basic_options, opt.optional, opt.others);

        logger.trace("raw: { Begin CLI\n", r, "\n} End CLI");
        return CliOption(r);
    }

    auto exit_status = ExitStatusType.Errors;

    if (category == "help") {
        writeln(main_opt, cliMergeCategory(), help_opt);
        exit_status = ExitStatusType.Ok;
    } else {
        import plugin.register;
        import std.range : takeOne;

        // dfmt off
        foreach (p; getRegisteredPlugins()
                 .filter!(p => p.category == category)
                 .takeOne) {
            exit_status = p.func(optTo(p.opts), CliArgs(args[1 .. $]));
        }
        // dfmt on
    }

    return exit_status;
}

auto parseMainCli(string[] args) {
    import std.algorithm : findAmong, filter, among;
    import std.array : array, empty;
    import std.typecons : Tuple, Yes, No;

    alias Rval = Tuple!(string, "category", Flag!"debug", "debug_", string[], "args");

    auto debug_ = findAmong(args, ["-d", "--debug"]).empty ? Flag!"debug".no : Flag!"debug".yes;
    // holds the remining arguments after -d/--debug has bee removed
    auto rem = args.filter!(a => !a.among("-d", "--debug")).array();

    if (rem.length <= 1) {
        return Rval("help", debug_, []);
    } else if (rem.length >= 2 && rem[1].among("help", "-h", "--help")) {
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
        confLogLevel(parsed.debug_);
        logger.trace(parsed);

        exit_status = doTestDouble(parsed.category, parsed.args);
    }
    catch (Exception ex) {
        collectException(logger.trace(text(ex)));
        exit_status = ExitStatusType.Errors;
    }

    return cast(typeof(return)) exit_status;
}
