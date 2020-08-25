/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains the functions that realize the plugin architecture.

All logger.XXX calls shall be dependent on the DebugLogging enum.
This is because this module otherwise produces a lot of junk logging that is
almost never relevant besides when making changes to this module.
*/
module application.plugin;

import my.path : AbsolutePath, Path;

import logger = std.experimental.logger;

/// Kind of plugin, part of the primary installation or found in DEXTOOL_PLUGINS.
enum Kind {
    /// A plugin that is found in the same directory as _this_ executable
    primary,
    /// A plugin found in the PATH
    secondary
}

/// Validated plugin with kind separating primary and secondar plugins.
struct Validated {
    Path path;
    Kind kind;
}

version (unittest) {
    import unit_threaded : shouldEqual;
}

// change this to true to activate debug logging for this module.
private enum DebugLogging = false;

private void nothrowTrace(T...)(auto ref T args) @safe nothrow {
    if (DebugLogging) {
        try {
            logger.trace(args);
        } catch (Exception ex) {
        }
    }
}

private void nothrowTracef(T...)(auto ref T args) @safe nothrow {
    if (DebugLogging) {
        try {
            logger.tracef(args);
        } catch (Exception ex) {
        }
    }
}

/// Scan for files in the same directory as the executable.
Validated[] scanForExecutables() {
    import std.algorithm : filter, map;
    import std.array : array;
    import std.file : thisExePath;
    import std.path : dirName, stripExtension, baseName;
    import std.range : tee;
    import my.file : which, whichFromEnv;

    auto pluginPattern = thisExePath.baseName.stripExtension ~ "*";

    auto primaryPlugins() {
        return which([AbsolutePath(thisExePath.dirName)], pluginPattern).map!(
                a => Validated(a, Kind.primary));
    }

    auto secondaryPlugins() {
        return whichFromEnv("DEXTOOL_PLUGINS", pluginPattern).map!(a => Validated(a,
                Kind.secondary));
    }

    static auto merge(T0, T1)(T0 primary, T1 secondary) {
        import std.range : chain;
        import my.set;

        // remove secondary that clash with primary.
        // secondaries may never override a primary.
        auto prim = toSet(primary.save.map!(a => cast(string) a.path));

        return chain(primary, secondary.filter!(a => a.path.baseName !in prim)).array;
    }

    return merge(primaryPlugins, secondaryPlugins).tee!(
            a => nothrowTrace("Found executable: ", a)).array;
}

/** Filter the filenames for those that fulfill the requirement for a plugin.
 *
 * Binaries that begin with <this binary>-* are plugins.
 */
auto filterValidPluginsThisExecutable(Validated[] fnames) @safe {
    import std.file : thisExePath;
    import std.path : baseName;

    immutable base_name = thisExePath.baseName ~ "-";
    return filterValidPlugins(fnames, base_name);
}

/** Filter the filenames for those that fulfill the requirement for a plugin.
 *
 * Binaries that begin with basename are plugins.
 */
auto filterValidPlugins(Validated[] fnames, string base_name) @safe {
    import std.algorithm : filter, startsWith, map;
    import std.range : tee;
    import std.path : baseName, absolutePath;

    // dfmt off
    return fnames
        .filter!(a => a.path.baseName.startsWith(base_name))
        .tee!(a => nothrowTrace("Valid plugin prefix: ", a));
    // dfmt on
}

/// Holds information for a discovered plugin.
struct Plugin {
    string name;
    string help;
    Path path;
    Kind kind;
}

private struct ExecuteResult {
    string output;
    bool isValid;
    Validated data;
}

ExecuteResult executePluginForShortHelp(Validated plugin) @safe nothrow {
    import std.process : execute;

    auto res = ExecuteResult("", false, plugin);

    try {
        res = ExecuteResult(execute([plugin.path, "--short-plugin-help"]).output, true, plugin);
    } catch (Exception ex) {
        nothrowTrace("No --short-plugin-help for: ", plugin);
    }

    nothrowTrace("Plugin --short-plugin-help: ", res);

    return res;
}

Plugin[] toPlugins(alias execFunc, T)(T plugins) @safe {
    import std.algorithm : filter, map, splitter, each, cache;
    import std.array : array;
    import std.ascii : newline;
    import std.range : tee;

    static struct Temp {
        string[] output;
        Validated data;
    }

    // dfmt off
    auto res = plugins
        .map!(a => execFunc(a))
        .cache
        // plugins that do not implement the required parameter are ignored
        .filter!(a => a.isValid)
        // the shorthelp must be two lines, the plugins name and a help text
        .map!(a => Temp(a.output.splitter(newline).array(), a.data))
        .filter!(a => a.output.length >= 2)
        // convert
        .map!(a => Plugin(a.output[0], a.output[1], a.data.path, a.data.kind))
        .array();
    // dfmt on

    try {
        res.each!(a => nothrowTracef("Found plugin '%s' (%s) (%s): %s", a.name,
                a.path, a.kind, a.help));
    } catch (Exception ex) {
    }

    return res;
}

string toShortHelp(Plugin[] plugins) @safe {
    import std.algorithm : map, joiner, reduce, max, copy, filter;
    import std.array : appender;
    import std.ascii : newline;
    import std.conv : text;
    import std.range : chain, only;
    import std.string : leftJustifier;

    // dfmt off
    // +1 so there is a space left between category and info
    auto max_length = 1 + reduce!((a,b) => max(a,b))(0UL, plugins.map!(a => a.name.length));

    auto app = appender!string();

    // dfmt off
    plugins
        .filter!(a => a.kind == Kind.primary)
        .map!(a =>
              chain(only("  "),
                    only(leftJustifier(a.name, max_length).text),
                    only(a.help))
              .joiner()
             )
        .joiner(newline)
        .text()
        .copy(app);

    app.put(newline);

    plugins
        .filter!(a => a.kind == Kind.secondary)
        .map!(a =>
              chain(only("  "),
                    only(leftJustifier(a.name, max_length).text),
                    only(a.help))
              .joiner()
             )
        .joiner(newline)
        .text()
        .copy(app);
    // dfmt on

    return app.data;
}

@("Shall only keep those files prefixed with basename")
@safe unittest {
    import std.algorithm;
    import std.array;

    auto fnames = ["/ignore", "/usr/bin/dextool", "/usr/bin/dextool-ctest"].map!(
            a => Validated(Path(a), Kind.primary)).array();

    filterValidPlugins(fnames, "dextool-").shouldEqual(
            [Validated(Path("/usr/bin/dextool-ctest"), Kind.primary)]);
}

@("Shall get the short text for the plugins")
@safe unittest {
    import std.algorithm;
    import std.array;

    auto fakeExec(Path plugin) {
        if (plugin == "dextool-ctest") {
            return ExecuteResult("ctest\nc test text", true,
                    Validated(Path("/a/dextool-ctest"), Kind.primary));
        } else if (plugin == "dextool-cpp") {
            return ExecuteResult("cpp\ncpp test text", true,
                    Validated(Path("/b/dextool-cpp"), Kind.primary));
        } else if (plugin == "dextool-too_many_lines") {
            return ExecuteResult("too_many_lines\n\nfoo", true);
        } else if (plugin == "dextool-fail_run") {
            return ExecuteResult("fail\nfoo", false);
        }

        assert(false); // should not happen
    }

    auto fake_plugins = [
        "dextool-ctest", "dextool-cpp", "dextool-too_many_lines",
        "dextool-fail_run"
    ].map!(a => Path(a)).array();

    toPlugins!fakeExec(fake_plugins).shouldEqual([
            Plugin("ctest", "c test text", Path("/a/dextool-ctest")),
            Plugin("cpp", "cpp test text", Path("/b/dextool-cpp")),
            Plugin("too_many_lines", "", Path(""))
            ]);
}

@("A short help text with two plugins")
@safe unittest {
    auto plugins = [
        Plugin("ctest", "c help text", Path("dummy"), Kind.primary),
        Plugin("cpp", "c++ help text", Path("dummy"), Kind.secondary)
    ];
    plugins.toShortHelp.shouldEqual("  ctest c help text\n  cpp   c++ help text");
}
