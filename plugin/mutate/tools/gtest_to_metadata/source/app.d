/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module app;

import logger = std.experimental.logger;
import std.algorithm;
import std.array;
import std.conv : to;
import std.format : format;
import std.path : relativePath;
import std.stdio : File;

import colorlog;
import my.path;

int main(string[] args) {
    import std.format : format;
    static import std.getopt;
    import std.file : thisExePath;
    import std.path : baseName;

    confLogger(VerboseMode.info);

    bool var;
    AbsolutePath[] searchDirs;
    auto relative = AbsolutePath(".");
    auto output = AbsolutePath("test_metadata.json");
    try {
        string[] searchDirsRaw;
        string relativeRaw;
        string outputRaw;
        auto helpInfo = std.getopt.getopt(args, std.getopt.config.required, "d|directory",
                "directory to search for googletest test cases", &searchDirsRaw,
                "r|relative", "paths are relative this path",
                &relativeRaw, "o|output", "write the json output to this file", &outputRaw);
        searchDirs = searchDirsRaw.map!(a => AbsolutePath(a)).array;
        if (!relativeRaw.empty)
            relative = AbsolutePath(relativeRaw);
        if (!outputRaw.empty)
            output = AbsolutePath(outputRaw);

        if (helpInfo.helpWanted) {
            std.getopt.defaultGetoptPrinter(format!"usage: %s <options>\n"(thisExePath.baseName),
                    helpInfo.options);
        }
    } catch (Exception e) {
        logger.error(e.msg);
        return 1;
    }

    auto testCases = appender!(TestCase[])();

    foreach (d; searchDirs) {
        logger.info("Searching ", d);
        try {
            import std.file : dirEntries, SpanMode;

            foreach (f; dirEntries(d.toString, SpanMode.depth).filter!"a.isFile"
                    .map!(a => AbsolutePath(a.name))) {
                logger.info("Parsing ", f);
                auto found = parse(f);
                foreach (tc; found)
                    logger.info("  ", tc.name, " at ", tc.line);
                testCases.put(found);
            }
        } catch (Exception e) {
        }
    }

    import std.json;

    auto jrval = appender!(JSONValue[])();

    foreach (testCase; testCases.data) {
        JSONValue tc;
        tc["name"] = testCase.name;
        JSONValue loc;
        loc["file"] = relativePath(testCase.file.toString, relative.toString);
        loc["line"] = testCase.line;
        tc["location"] = loc;

        jrval.put(tc);
    }

    logger.info("Saving result to ", output);
    File(output.toString, "w").write(JSONValue(jrval.data).toPrettyString);

    return 0;
}

struct TestCase {
    AbsolutePath file;
    uint line;
    string name;
}

TestCase[] parse(AbsolutePath testPath) {
    import std.ascii : isWhite;
    import std.string : startsWith, strip;

    static TestCase parseTest(string[] lines) {
        TestCase tc;
        string def;
        bool open;
        int parenthesis;

        foreach (c; lines.joiner) {
            if (c == '(') {
                open = true;
                parenthesis++;
            } else if (c == ')')
                parenthesis--;
            else if (parenthesis == 1 && !c.isWhite)
                def ~= c;

            if (open && parenthesis == 0)
                break;
        }

        auto s = split(def, ',');
        if (s.length == 2 && !s[0].empty && !s[1].empty) {
            tc.name = format!"%s.%s"(s[0].strip, s[1].strip);
        }

        return tc;
    }

    static TestCase parseTestParam(string[] lines) {
        TestCase tc;
        string def;
        bool open;
        int commas;

        foreach (c; lines.joiner) {
            if (c == '(')
                open = true;
            else if (c == ',')
                commas++;
            else if (open && !c.isWhite)
                def ~= c;

            if (open && commas == 2)
                break;
        }

        if (def.empty)
            return tc;

        auto s = split(def[0 .. $ - 1], ',');
        if (s.length == 2 && !s[0].empty && !s[1].empty)
            tc.name = format!"%s.%s"(s[0].strip, s[1].strip);

        return tc;
    }

    alias Parser = TestCase function(string[]);
    Parser[string] parsers;
    parsers["TEST"] = &parseTest;
    parsers["TEST_F"] = &parseTest;
    parsers["TEST_P"] = &parseTest;
    parsers["INSTANTIATE_TEST_SUITE_P"] = &parseTestParam;

    auto lines = File(testPath.toString).byLineCopy.array;

    auto testCases = appender!(TestCase[])();

    foreach (i; 0 .. lines.length) {
        () {
            foreach (p; parsers.byKeyValue) {
                try {
                    if (lines[i].startsWith(p.key)) {
                        auto tc = p.value()(lines[i .. $]);
                        tc.line = cast(uint) i + 1;
                        tc.file = testPath;
                        if (!tc.name.empty)
                            testCases.put(tc);
                        return;
                    }
                } catch (Exception e) {
                    logger.info(e.msg);
                }
            }
        }();
    }

    return testCases.data;
}
