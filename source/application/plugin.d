/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains the functions that realize the plugin architecture.
*/
module application.plugin;

import dextool.type : FileName;

import logger = std.experimental.logger;

version (unittest) {
    import unit_threaded : shouldEqual;
}

private void nothrowTrace(T...)(auto ref T args) @safe nothrow {
    try {
        logger.trace(args);
    }
    catch (Exception ex) {
    }
}

/// Scan for files in the same directory as the executable.
FileName[] scanForExecutables() {
    import std.algorithm : filter, map;
    import std.array : array;
    import std.file : thisExePath, dirEntries, SpanMode;
    import std.path : absolutePath, dirName;
    import std.range : tee;

    bool isExecutable(uint attrs) {
        import core.sys.posix.sys.stat;

        // is a regular file and any of owner/group/other have execute
        // permission
        return (attrs & S_IFMT) == S_IFREG && ((attrs & (S_IXUSR | S_IXGRP | S_IXOTH)) != 0);
    }

    // dfmt off
    return dirEntries(thisExePath.dirName, SpanMode.shallow)
        .filter!(a => isExecutable(a.attributes))
        .map!(a => FileName(a.name.absolutePath))
        .tee!(a => logger.trace("Found executable: ", cast(string) a))
        .array();
    // dfmt on
}

/** Filter the filenames for those that fulfill the requirement for a plugin.
 *
 * Binaries that begin with <this binary>-* are plugins.
 */
auto filterValidPluginsThisExecutable(FileName[] fnames) @safe {
    import std.file : thisExePath;
    import std.path : baseName;

    immutable base_name = thisExePath.baseName ~ "-";
    return filterValidPlugins(fnames, base_name);
}

/** Filter the filenames for those that fulfill the requirement for a plugin.
 *
 * Binaries that begin with basename are plugins.
 */
auto filterValidPlugins(FileName[] fnames, string base_name) @safe {
    import std.algorithm : filter, startsWith, map;
    import std.range : tee;
    import std.path : baseName, absolutePath;

    // dfmt off
    return fnames
        .filter!(a => a.baseName.startsWith(base_name))
        .tee!(a => nothrowTrace("Valid plugin prefix: ", cast(string) a))
        .map!(a => FileName(a));
    // dfmt on
}

struct Plugin {
    string name;
    string help;
    FileName path;
}

private struct ExecuteResult {
    string output;
    bool isValid;
    FileName path;
}

ExecuteResult executePluginForShortHelp(FileName plugin) @safe nothrow {
    import std.process : execute;

    auto res = ExecuteResult("", false, plugin);

    try {
        res = ExecuteResult(execute([plugin, "--short-plugin-help"]).output, true, plugin);
    }
    catch (Exception ex) {
        nothrowTrace("No --short-plugin-help for: ", plugin);
    }

    nothrowTrace("Plugin --short-plugin-help: ", res);

    return res;
}

Plugin[] toPlugins(alias execFunc, T)(T plugins) @safe nothrow {
    import std.algorithm : filter, map, splitter, each, cache;
    import std.array : array;
    import std.ascii : newline;
    import std.range : tee;

    static struct Temp {
        string[] output;
        FileName path;
    }

    // dfmt off
    auto res = plugins
        .map!(a => execFunc(a))
        .cache
        // plugins that do not implement the required parameter are ignored
        .filter!(a => a.isValid)
        // the shorthelp must be two lines, the plugins name and a help text
        .map!(a => Temp(a.output.splitter(newline).array(), a.path))
        .filter!(a => a.output.length >= 2)
        // convert
        .map!(a => Plugin(a.output[0], a.output[1], a.path))
        .array();
    // dfmt on

    try {
        res.each!(a => logger.tracef("Found plugin '%s' (%s): %s", a.name, a.path, a.help));
    }
    catch (Exception ex) {
    }

    return res;
}

string toShortHelp(Plugin[] plugins) @safe {
    import std.algorithm : map, joiner, reduce, max;
    import std.ascii : newline;
    import std.conv : text;
    import std.range : chain, only;
    import std.string : leftJustifier;

    // dfmt off
    // +1 so there is a space left between category and info
    auto max_length = 1 + reduce!((a,b) => max(a,b))(0UL, plugins.map!(a => a.name.length));

    return plugins
        .map!(a =>
              chain(only("  "),
                    only(leftJustifier(a.name, max_length).text),
                    only(a.help))
              .joiner()
             )
        .joiner(newline)
        .text();
    // dfmt on
}

@("Shall only keep those files prefixed with basename")
@safe unittest {
    import std.algorithm;
    import std.array;

    auto fnames = ["/ignore", "/usr/bin/dextool", "/usr/bin/dextool-ctest"].map!(
            a => FileName(a)).array();

    filterValidPlugins(fnames, "dextool-").shouldEqual([FileName("/usr/bin/dextool-ctest")]);
}

@("Shall get the short text for the plugins")
@safe unittest {
    import std.algorithm;
    import std.array;

    auto fakeExec(FileName plugin) {
        if (plugin == "dextool-ctest") {
            return ExecuteResult("ctest\nc test text", true, FileName("/a/dextool-ctest"));
        } else if (plugin == "dextool-cpp") {
            return ExecuteResult("cpp\ncpp test text", true, FileName("/b/dextool-cpp"));
        } else if (plugin == "dextool-too_many_lines") {
            return ExecuteResult("too_many_lines\n\nfoo", true);
        } else if (plugin == "dextool-fail_run") {
            return ExecuteResult("fail\nfoo", false);
        }

        assert(false); // should not happen
    }

    auto fake_plugins = ["dextool-ctest", "dextool-cpp",
        "dextool-too_many_lines", "dextool-fail_run"].map!(a => FileName(a)).array();

    toPlugins!fakeExec(fake_plugins).shouldEqual([Plugin("ctest", "c test text",
            FileName("/a/dextool-ctest")), Plugin("cpp", "cpp test text",
            FileName("/b/dextool-cpp"))]);
}

@("A short help text with two plugins")
@safe unittest {
    auto plugins = [Plugin("ctest", "c help text"), Plugin("cpp", "c++ help text")];
    plugins.toShortHelp.shouldEqual("  ctest c help text\n  cpp   c++ help text");
}
