/**
Date: 2015-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module application.app_main;

import std.typecons : Flag;

import logger = std.experimental.logger;

import dextool.type;
import dextool.logger;
import plugin.types : CliBasicOption;

version (unittest) {
    import unit_threaded;
}

enum string main_opt = `usage:
 dextool <command> [options] [<args>...]

options:
 -h, --help         show this global help
 -d, --debug        turn on debug output for detailed tracing
 --version          print the version of dextool

commands:
  help
`;

enum CliBasicOption basic_options = "
 -h, --help         show this help
";

enum string help_opt = "

See 'dextool <command> -h' to read about a specific subcommand.
";

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
                    only(leftJustifier(a.category, max_length + 1).text),
                    only(a.categoryCliInfo))
              .joiner()
             )
        .joiner(newline)
        .text();
    // dfmt on
}

ExitStatusType doTestDouble(CliCategoryStatus status, string category, string[] args) {
    import std.stdio : writeln;

    auto exit_status = ExitStatusType.Errors;

    final switch (status) with (CliCategoryStatus) {
    case Help:
        writeln(main_opt, cliMergeCategory(), help_opt);
        exit_status = ExitStatusType.Ok;
        break;
    case Version:
        import dextool.utility : dextoolVersion;

        writeln("dextool version ", dextoolVersion);
        exit_status = ExitStatusType.Ok;
        break;
    case NoCategory:
        logger.error("No such main category: " ~ category);
        logger.error("-h to list accetable categories");
        exit_status = ExitStatusType.Errors;
        break;
    case Category:
        import std.algorithm : filter;
        import std.range : takeOne;
        import plugin.register : getRegisteredPlugins, CliArgs;

        bool match_found;

        // dfmt off
        // find the first plugin matching the category
        foreach (p; getRegisteredPlugins()
                 .filter!(p => p.category == category)
                 .takeOne) {
            exit_status = p.func(basic_options, CliArgs(args[1 .. $]));
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

private struct MainCliReturnType {
    CliCategoryStatus status;
    string category;
    ConfigureLog confLog;
    string[] args;
}

/** Parse the raw command line.
 *
 * Flags handled by parseMainCli are removed from the reminding args in the
 * return value.
 */
auto parseMainCli(string[] args) {
    import std.algorithm : findAmong, filter, among;
    import std.array : array, empty;

    ConfigureLog debug_ = findAmong(args, ["-d", "--debug"]).empty
        ? ConfigureLog.info : ConfigureLog.debug_;
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
        result.confLog.shouldEqual(ConfigureLog.debug_);
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
        confLogLevel(parsed.confLog);
        logger.trace(parsed);

        exit_status = doTestDouble(parsed.status, parsed.category, parsed.args);
    }
    catch (Exception ex) {
        collectException(logger.trace(text(ex)));
        exit_status = ExitStatusType.Errors;
    }

    if (exit_status != ExitStatusType.Ok) {
        try {
            logger.errorf("Dextool exiting due to runtime error");
        }
        catch (Exception ex) {
        }
    }

    return cast(typeof(return)) exit_status;
}
