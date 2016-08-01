// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module application.app_main;

import std.stdio : writeln, writefln, stderr;
import std.typecons : Flag, Tuple;

import logger = std.experimental.logger;

import application.types;

// Workaround for undefined identifiers during compilation.
// The problem is probably in ast.visitor or ast.node but I don't know why.
import cpptooling.analyzer.clang.ast.visitor;

version (unittest) {
    import unit_threaded;
}

/// Version derived from the git archive.
enum app_version = import("version.txt");

static assert(app_version.length > 0, "Failed to import version.txt at compile time");

enum string main_opt = "usage:
 dextool <command> [options] [<args>...]

options:
 -h, --help         show this help
 -d, --debug        turn on debug output for tracing of generator flow
 --version          print the version of dextool

commands:
  help
";

enum string basic_options = "
 -h, --help         show this help
 -d, --debug        turn on debug output for tracing of generator flow
";

enum string help_opt = "
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

class DebugLogger : logger.Logger {
    import std.conv;

    int line = -1;
    string file = null;
    string func = null;
    string prettyFunc = null;
    string msg = null;
    logger.LogLevel lvl;

    this(const logger.LogLevel lv = logger.LogLevel.trace) {
        super(lv);
    }

    override void writeLogMsg(ref LogEntry payload) @trusted {
        this.line = payload.line;
        this.file = payload.file;
        this.func = payload.funcName;
        this.prettyFunc = payload.prettyFuncName;
        this.lvl = payload.logLevel;
        this.msg = payload.msg;

        if (this.line == -1) {
            stderr.writefln("%s: %s", text(this.lvl), this.msg);
        } else {
            // Example of standard: 2016-05-01T22:31:54.019:type.d:retrieveType:159 c:@S@Foo:struct Foo
            stderr.writefln("%s: %s [%s:%d]", text(this.lvl), this.msg, this.func, this.line);
        }
    }
}

void confLogLevel(Flag!"debug" debug_) {
    import std.exception;
    import std.experimental.logger.core : sharedLog;

    try {
        if (debug_) {
            logger.globalLogLevel(logger.LogLevel.all);
            auto logger_ = new DebugLogger();
            logger.sharedLog(logger_);
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

ExitStatusType doTestDouble(CliCategoryStatus status, string category, string[] args) {
    import std.algorithm;
    import std.traits;

    // load the plugin system
    import plugin.loader;
    import plugin.types;

    static auto optTo(CliOptionParts opt) {
        import std.format;

        const auto r = format("%s

options:%s%s

%s", opt.usage, basic_options, opt.optional, opt.others);

        debug logger.trace("raw: { Begin CLI\n", r, "\n} End CLI");
        return CliOption(r);
    }

    auto exit_status = ExitStatusType.Errors;

    final switch (status) with (CliCategoryStatus) {
    case Help:
        writeln(main_opt, cliMergeCategory(), help_opt);
        exit_status = ExitStatusType.Ok;
        break;
    case Version:
        writeln("dextool version ", app_version);
        exit_status = ExitStatusType.Ok;
        break;
    case NoCategory:
        logger.error("No such main category: " ~ category);
        logger.error("-h to list accetable categories");
        exit_status = ExitStatusType.Errors;
        break;
    case Category:
        import plugin.register;
        import std.range : takeOne;

        bool match_found;

        // dfmt off
        foreach (p; getRegisteredPlugins()
                 .filter!(p => p.category == category)
                 .takeOne) {
            exit_status = p.func(optTo(p.opts), CliArgs(args[1 .. $]));
            match_found = true;
        }
        // dfmt on

        if (!match_found) {
            // print error message to user as if no category was found
            exit_status = doTestDouble(CliCategoryStatus.NoCategory, category, []);
        }

        break;
    }

    return exit_status;
}

private enum CliCategoryStatus {
    Help,
    Version,
    NoCategory,
    Category
}

private alias MainCliReturnType = Tuple!(CliCategoryStatus, "status", string,
        "category", Flag!"debug", "debug_", string[], "args");

/** Parse the raw command line.
 *
 * Flags handled by parseMainCli are removed from the reminding args in the
 * return value.
 */
auto parseMainCli(string[] args) {
    import std.algorithm : findAmong, filter, among;
    import std.array : array, empty;
    import std.typecons : Yes, No;

    auto debug_ = cast(Flag!"debug") !findAmong(args, ["-d", "--debug"]).empty;
    // holds the remining arguments after -d/--debug has bee removed
    auto remining_args = args.filter!(a => !a.among("-d", "--debug")).array();

    string category = remining_args.length >= 2 ? remining_args[1] : "";
    auto state = CliCategoryStatus.Category;
    if (remining_args.length <= 1) {
        state = CliCategoryStatus.NoCategory;
        remining_args = [];
    } else if (remining_args.length >= 2 && remining_args[1].among("help", "-h", "--help")) {
        state = CliCategoryStatus.Help;
        remining_args = [];
    } else if (remining_args.length >= 2 && remining_args[1].among("--version")) {
        state = CliCategoryStatus.Version;
        remining_args = [];
    }

    return MainCliReturnType(state, category, debug_, remining_args);
}

version (unittest) {
    import std.algorithm : findAmong;
    import std.array : empty;

    // May seem unnecessary testing to test the CLI but bugs have been
    // introduced accidentaly in parseMainCli.
    // It is also easier to test "main CLI" here because it takes the least
    // setup and has no side effects.

    @Name("Should be no category")
    unittest {
        parseMainCli(["dextool"]).status.shouldEqual(CliCategoryStatus.NoCategory);
    }

    @Name("Should flag that debug mode is to be activated")
    @Values("-d", "--debug")
    unittest {
        auto result = parseMainCli(["dextool", getValue!string]);
        result.debug_.shouldBeTrue;
        findAmong(result.args, ["-d", "--debug"]).empty.shouldBeTrue;
    }

    @Name("Should be the version category")
    unittest {
        auto result = parseMainCli(["dextool", "--version"]);
        result.status.shouldEqual(CliCategoryStatus.Version);
        result.args.length.shouldEqual(0);
    }

    @Name("Should be the help category")
    @Values("help", "-h", "--help")
    unittest {
        auto result = parseMainCli(["dextool", getValue!string]);
        result.status.shouldEqual(CliCategoryStatus.Help);
        result.args.length.shouldEqual(0);
    }
}

int rmain(string[] args) nothrow {
    import std.conv;
    import std.exception;

    ExitStatusType exit_status = ExitStatusType.Errors;

    try {
        auto parsed = parseMainCli(args);
        confLogLevel(parsed.debug_);
        logger.trace(parsed);

        exit_status = doTestDouble(parsed.status, parsed.category, parsed.args);
    }
    catch (Exception ex) {
        collectException(logger.trace(text(ex)));
        exit_status = ExitStatusType.Errors;
    }

    if (exit_status != ExitStatusType.Ok) {
        try {
            logger.errorf(
                    "Dextool exiting due to runtime error. Run with --debug for more information");
        }
        catch (Exception ex) {
        }
    }

    return cast(typeof(return)) exit_status;
}
