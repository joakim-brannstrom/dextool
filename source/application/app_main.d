/**
Date: 2015-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module application.app_main;

import logger = std.experimental.logger;

import dextool.type : FileName, ExitStatusType;
import dextool.logger : ConfigureLog;

version (unittest) {
    import unit_threaded : shouldEqual, Values, getValue;
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

enum string basic_options = "
 -h, --help         show this help
";

enum string help_opt = "

See 'dextool <command> -h' to read about a specific subcommand.
";

private enum CLICategoryStatus {
    Help,
    Version,
    NoCategory,
    Category
}

private struct CLIResult {
    CLICategoryStatus status;
    string category;
    ConfigureLog confLog;
}

/** Parse the raw command line.
 */
auto parseMainCLI(string[] args) {
    import std.algorithm : findAmong, filter, among;
    import std.array : array, empty;
    import dextool.logger;

    ConfigureLog loglevel = findAmong(args, ["-d", "--debug"]).empty
        ? ConfigureLog.info : ConfigureLog.debug_;
    // holds the remining arguments after -d/--debug has bee removed
    auto remining_args = args.filter!(a => !a.among("-d", "--debug")).array();

    auto state = CLICategoryStatus.Category;

    if (remining_args.length <= 1) {
        state = CLICategoryStatus.NoCategory;
    } else if (remining_args.length >= 2 && remining_args[1].among("help", "-h", "--help")) {
        state = CLICategoryStatus.Help;
    } else if (remining_args.length >= 2 && remining_args[1].among("--version")) {
        state = CLICategoryStatus.Version;
    }

    string category = remining_args.length >= 2 ? remining_args[1] : "";

    return CLIResult(state, category, loglevel);
}

version (unittest) {
    import std.algorithm : findAmong;
    import std.array : empty;

    // May seem unnecessary testing to test the CLI but bugs have been
    // introduced accidentaly in parseMainCLI.
    // It is also easier to test "main CLI" here because it takes the least
    // setup and has no side effects.

    @("Should be no category")
    unittest {
        parseMainCLI(["dextool"]).status.shouldEqual(CLICategoryStatus.NoCategory);
    }

    @("Should flag that debug mode is to be activated")
    @Values("-d", "--debug")
    unittest {
        auto result = parseMainCLI(["dextool", getValue!string]);
        result.confLog.shouldEqual(ConfigureLog.debug_);
    }

    @("Should be the version category")
    unittest {
        auto result = parseMainCLI(["dextool", "--version"]);
        result.status.shouldEqual(CLICategoryStatus.Version);
    }

    @("Should be the help category")
    @Values("help", "-h", "--help")
    unittest {
        auto result = parseMainCLI(["dextool", getValue!string]);
        result.status.shouldEqual(CLICategoryStatus.Help);
    }
}

ExitStatusType runPlugin(CLIResult cli, string[] args) {
    import std.stdio : writeln;
    import application.plugin;
    import dextool.cli_help;

    auto exit_status = ExitStatusType.Errors;

    auto plugins = scanForExecutables.filterValidPluginsThisExecutable
        .toPlugins!executePluginForShortHelp;

    final switch (cli.status) with (CLICategoryStatus) {
    case Help:
        writeln(main_opt, plugins.toShortHelp, help_opt);
        exit_status = ExitStatusType.Ok;
        break;
    case Version:
        import dextool.utility : dextoolVersion;

        writeln("dextool version ", dextoolVersion);
        exit_status = ExitStatusType.Ok;
        break;
    case NoCategory:
        logger.error("No such main category: " ~ cli.category);
        logger.error("-h to list accetable categories");
        exit_status = ExitStatusType.Errors;
        break;
    case Category:
        import std.algorithm : filter;
        import std.process : spawnProcess, wait;
        import std.range : takeOne;

        bool match_found;

        // dfmt off
        // find the first plugin matching the category
        foreach (p; plugins
                 .filter!(p => p.name == cli.category)
                 .takeOne) {
            auto pid = spawnProcess([cast(string) p.path] ~ args[1 .. $]);
            exit_status = wait(pid) == 0 ? ExitStatusType.Ok : ExitStatusType.Errors;
            match_found = true;
        }
        // dfmt on

        if (!match_found) {
            // print error message to user as if no category was found
            auto tmp = CLIResult(CLICategoryStatus.NoCategory);
            exit_status = runPlugin(tmp, []);
        }

        break;
    }

    return exit_status;
}

int rmain(string[] args) nothrow {
    import std.conv : text;
    import std.exception;
    import dextool.logger : confLogLevel;

    ExitStatusType exit_status = ExitStatusType.Errors;

    try {
        auto parsed = parseMainCLI(args);
        confLogLevel(parsed.confLog);
        logger.trace(parsed);

        exit_status = runPlugin(parsed, args);
    }
    catch (Exception ex) {
        collectException(logger.trace(text(ex)));
        exit_status = ExitStatusType.Errors;
    }

    if (exit_status != ExitStatusType.Ok) {
        try {
            logger.errorf("exiting...");
        }
        catch (Exception ex) {
        }
    }

    return cast(int) exit_status;
}
