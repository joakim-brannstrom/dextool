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

    bool filterFailing;
    string confFile;
    string[] postParam;
    string[] preParam;
    string[] searchDir;
    // dfmt off
    auto helpInfo = std.getopt.getopt(args,
        "filter-failing", "execute each command and remove those that fail executing", &filterFailing,
        "post-param", "parameters to append the commands such as flags", &postParam,
        "pre-param", "parameters to prepend the commands with such as scripts", &preParam,
        std.getopt.config.required, "test-cmd-dir", "directory to search for executables", &searchDir,
        std.getopt.config.required, "conf", "configuration file to update", &confFile,
        );
    // dfmt on
    if (helpInfo.helpWanted) {
        std.getopt.defaultGetoptPrinter(format("usage: %s\n", args[0]), helpInfo.options);
        return 1;
    }

    auto cmds = appender!(string[][])();
    auto failing = appender!(string[][])();
    foreach (a; searchDir.map!(a => dirEntries(a, SpanMode.depth))
            .joiner
            .filter!(a => a.isFile && a.name.isExecutable)) {
        auto cmd = preParam ~ a.name ~ postParam;
        if (!filterFailing) {
            cmds.put(cmd);
        } else if (spawnProcess(cmd).wait == 0) {
            cmds.put(cmd);
        } else {
            failing.put(cmd);
        }
    }

    const tmpFile = confFile ~ ".tmp";
    auto fout = File(tmpFile, "w");

    bool doInjection = true;
    foreach (l; File(confFile).byLineCopy) {
        if (l.startsWith("test_cmd") && doInjection) {
            fout.writefln(`test_cmd = [%-(%s, %)]`, cmds.data.map!(a => format(`[%(%s, %)]`, a)));
            writeln("Updated test_cmd");
            if (!failing.data.empty) {
                fout.writefln(`# failing [%-(%s, %)]`,
                        failing.data.map!(a => format(`[%(%s, %)]`, a)));
                writeln("Failing ", failing.data);
            }
            doInjection = false;
        } else {
            fout.writeln(l);
        }
    }

    rename(tmpFile, confFile);

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
