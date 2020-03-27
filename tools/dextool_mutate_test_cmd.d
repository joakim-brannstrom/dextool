#!/usr/bin/env rdmd
/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Look for binaries in a directory and generate a test_cmd config for them to be
used in a dextool mutate configuration file. This is useful when the automatic
discovery with test_cmd_dir isn't suitable because some binaries has to be
manually removed.
*/

import logger = std.experimental.logger;
import std;

int main(string[] args) {
    static import std.getopt;

    string[] searchDir;
    string[] extraFlags;
    bool filterFailing;
    // dfmt off
    auto helpInfo = std.getopt.getopt(args,
        "test-cmd-dir", "directory to search for executables", &searchDir,
        "flag", "flags to append to the commands", &extraFlags,
        "filter-failing", "execute a test binary and remove it if it fails", &filterFailing,
        );
    // dfmt on
    if (helpInfo.helpWanted) {
        std.getopt.defaultGetoptPrinter(format("usage: %s\n", args[0]), helpInfo.options);
        return 1;
    }

    auto cmds = appender!(string[])();
    auto failing = appender!(string[])();
    foreach (a; searchDir.map!(a => dirEntries(a, SpanMode.depth))
            .joiner
            .filter!(a => a.isFile && a.name.isExecutable)) {
        int exitCode;
        if (filterFailing) {
            exitCode = spawnProcess([a.name] ~ extraFlags).wait;
        }
        if (exitCode == 0) {
            cmds.put(a.name);
        } else {
            failing.put(a.name);
        }
    }

    const flags = extraFlags.empty ? "" : format(`, %(%s, %)`, extraFlags);
    writefln(`test_cmd = [%-(%s, %)]`, cmds.data.map!(a => format(`["%s"%s]`, a, flags)));
    if (!failing.data.empty)
        writeln(`# failing `, failing.data);

    return 0;
}

bool isExecutable(string p) nothrow {
    import core.sys.posix.sys.stat;
    import std.file : getAttributes;
    import std.file : dirEntries, SpanMode;

    try {
        return (getAttributes(p) & S_IXUSR) != 0;
    } catch (Exception e) {
    }
    return false;
}
