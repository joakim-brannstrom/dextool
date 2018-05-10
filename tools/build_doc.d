#!/usr/bin/env rdmd
/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/

import core.stdc.stdlib;
import std.algorithm;
import std.array;
import std.ascii;
import std.conv;
import std.file;
import std.process;
import std.path;
import std.range;
import std.stdio;
import std.string;
import logger = std.experimental.logger;

int main(string[] args) {
    static import std.getopt;

    std.getopt.GetoptResult help_info;
    string final_html_dir;
    bool help;
    bool ddox;
    try {
        // dfmt off
        help_info = std.getopt.getopt(args, std.getopt.config.passThrough,
            std.getopt.config.keepEndOfOptions,
            "ddox", "build the documentation with ddox", &ddox,
            "output", "directory to move the generated documentation to", &final_html_dir,
            );
        // dfmt on
        help = help_info.helpWanted;
    } catch (std.getopt.GetOptException e) {
        // unknown option
        help = true;
        logger.error(e.msg);
    } catch (Exception e) {
        help = true;
        logger.error(e.msg);
    }

    void printHelp() {
        import std.getopt : defaultGetoptPrinter;
        import std.format : format;
        import std.path : baseName;

        defaultGetoptPrinter(format("usage: %s\n", args[0].baseName), help_info.options);
    }

    if (help) {
        printHelp;
        return 0;
    }

    spawnShell("dub fetch ddox").wait;

    string[] docs;
    auto dirs = ["."];
    while (dirs.length != 0) {
        auto cur = dirs[0];
        dirs = dirs[1 .. $];

        dirs ~= dirEntries(cur, SpanMode.shallow).filter!(a => a.isDir
                && !a.isSymlink).map!(a => a.name).array;
        docs ~= dirEntries(cur, SpanMode.shallow).filter!(a => a.isFile
                && !a.isSymlink).filter!(a => a.name.endsWith("_docs.json"))
            .map!(a => a.name).array;
    }
    writefln("Found %s", docs);

    string[] doc_paths;
    string[] failed_docs;
    foreach (df; docs) {
        auto dest = buildPath("api", df.baseName.stripExtension);
        doc_paths ~= buildPath(dest, "index.html");
        mkdirRecurse(dest);

        bool sum_ecode = true;

        if (ddox) {
            sum_ecode = spawnShell("dub run ddox -- filter --min-protection Public " ~ df).wait == 0;
            sum_ecode = sum_ecode
                && spawnShell("dub run ddox -- generate-html " ~ df ~ " " ~ dest).wait == 0;
        } else {
            sum_ecode = spawnShell(format("cp -r %s/* %s", buildPath(df.dirName, "docs_dmd"), dest)).wait
                == 0;
        }

        if (!sum_ecode)
            failed_docs ~= df;
    }

    if (failed_docs.length != 0) {
        writefln("Failed building doc for %s", failed_docs);
    }

    auto fmd = File("docs.md", "w");
    fmd.writeln("# API Documentation");
    foreach (p; doc_paths) {
        fmd.writefln(" * [%s](%s)", p.dirName, p);
    }

    if (final_html_dir.length != 0) {
        mkdirRecurse(final_html_dir);
        spawnShell("cp -r api " ~ final_html_dir);
    }

    return 0;
}
