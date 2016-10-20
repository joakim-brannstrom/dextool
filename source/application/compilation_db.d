// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Utility functions for supporting a Clang Compilation Database.

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module application.compilation_db;

import std.typecons : Nullable, Tuple;
import logger = std.experimental.logger;

import application.types;

version (unittest) {
    import unit_threaded : Name, shouldEqual;
    import test.extra_should : shouldEqualPretty;
} else {
    private struct Name {
        string name_;
    }
}

/// Hold an entry from the compilation database
struct CompileCommand {
    struct FileName {
        string payload;
        alias payload this;
    }

    struct AbsoluteFileName {
        string payload;
        alias payload this;
    }

    struct Directory {
        string payload;
        alias payload this;
    }

    struct Command {
        string payload;
        alias payload this;
    }

    FileName file;
    AbsoluteFileName absoluteFile;
    Directory directory;
    Command command;
}

struct CompileDbJsonPath {
    string payload;
    alias payload this;
}

struct CompileCommandDB {
    CompileCommand[] payload;
    alias payload this;
}
// The result of searching for a file in a compilation DB.
// The file may be occur more than one time therefor an array.
struct CompileCommandSearch {
    CompileCommand[] payload;
    alias payload this;
}

/** Parse a CompilationDatabase.
 *
 * Params:
 *  raw_input = the content of the CompilationDatabase.
 *  in_file = path to the compilation database file.
 *  out_range = range to write the output to.
 */
private void parseCommands(T)(string raw_input, CompileDbJsonPath in_file, ref T out_range) nothrow {
    import std.path : dirName;
    import std.json;

    static Nullable!CompileCommand toCompileCommand(JSONValue v, CompileDbJsonPath in_file) nothrow {
        import std.path : buildNormalizedPath, absolutePath;
        import logger = cpptooling.utility.logger;

        // expects that v is a tuple of 3 json values with the keys
        // directory, command, file

        Nullable!CompileCommand rval;

        try {
            string abs_workdir = buildNormalizedPath(in_file, v["directory"].str);
            string abs_file = buildNormalizedPath(abs_workdir, v["file"].str);
            auto tmp = CompileCommand(CompileCommand.FileName(v["file"].str),
                    CompileCommand.AbsoluteFileName(abs_file),
                    CompileCommand.Directory(abs_workdir), CompileCommand.Command(v["command"].str));
            rval = tmp;
        }
        catch (Exception ex) {
            logger.error("Unable to parse json attribute: " ~ ex.msg);
        }

        return rval;
    }

    static void put(T)(JSONValue v, CompileDbJsonPath in_file, ref T out_range) nothrow {
        import std.algorithm : map, filter;
        import std.array : array;
        import logger = cpptooling.utility.logger;

        try {
            // dfmt off
            foreach (e; v.array()
                     // map the JSON tuples to D structs
                     .map!(a => toCompileCommand(a, in_file))
                     // remove invalid
                     .filter!(a => !a.isNull)
                     .map!(a => a.get)) {
                out_range.put(e);
            }
            // dfmt on
        }
        catch (Exception ex) {
            logger.error("Unable to parse json:" ~ ex.msg);
        }
    }

    try {
        auto json = parseJSON(raw_input);
        auto as_dir = CompileDbJsonPath(in_file.dirName);
        put(json, as_dir, out_range);
    }
    catch (JSONException ex) {
        import cpptooling.utility.logger : error;

        error("Error while parsing compilation database: " ~ ex.msg);
    }
    catch (Exception ex) {
        import cpptooling.utility.logger : error;

        error("Error while parsing compilation database: " ~ ex.msg);
    }
}

void fromFile(T)(CompileDbJsonPath filename, ref T app) {
    import std.algorithm : joiner;
    import std.conv : text;
    import std.stdio : File;

    auto raw = File(cast(string) filename).byLineCopy.joiner.text;
    raw.parseCommands(filename, app);
}

void fromFiles(T)(CompileDbJsonPath[] fnames, ref T app) {
    foreach (f; fnames) {
        f.fromFile(app);
    }
}

/** Return default path if argument is null.
 */
CompileDbJsonPath[] orDefaultDb(string[] cli_path) @safe pure nothrow {
    import std.array : array;
    import std.algorithm : map;

    if (cli_path is null) {
        return [CompileDbJsonPath("compile_commands.json")];
    }

    return cli_path.map!(a => CompileDbJsonPath(a)).array();
}

/** Contains the results of a search in the compilation database.
 *
 * When searching for the compile command for a file, the compilation db can
 * return several commands, as the file may have been compiled with different
 * options in different parts of the project.
 *
 * Params:
 *  filename = either relative or absolute filename to use as key when searching in the db.
 */
CompileCommandSearch find(CompileCommandDB db, string filename) @safe pure
in {
    import std.path : isAbsolute;
    import cpptooling.utility.logger;

    debug trace("Looking for " ~ (filename.isAbsolute ? "absolute" : "relative") ~ " " ~ filename);
}
out (result) {
    import std.conv : to;
    import cpptooling.utility.logger;

    debug trace("Found " ~ to!string(result));
}
body {
    import std.algorithm : find;
    import std.path : isAbsolute;
    import std.range : takeOne;

    @safe pure bool function(CompileCommand a, string b) comparer;

    if (filename.isAbsolute) {
        comparer = (a, b) @safe pure{
            return a.absoluteFile.length == b.length && a.absoluteFile == b;
        };
    } else {
        comparer = (a, b) @safe pure{
            return a.file.length == b.length && a.file == b;
        };
    }

    auto found = find!(comparer)(cast(CompileCommand[]) db, filename).takeOne;

    return CompileCommandSearch(found);
}

private alias SearchResult = Tuple!(string[], "cflags", string, "absoluteFile");

/** Append the compiler flags if a match is found in the DB or error out.
 */
Nullable!(SearchResult) appendOrError(CompileCommandDB compile_db,
        in string[] cflags, in string input_file) @safe {
    import application.compilation_db : find, toString;

    auto compile_commands = compile_db.find(input_file.idup);
    debug {
        logger.trace(compile_commands.length > 0,
                "CompilationDatabase match (by filename):\n", compile_commands.toString);
        if (compile_commands.length == 0) {
            logger.trace(compile_db.toString);
        }
    }

    typeof(return) rval;
    if (compile_commands.length == 0) {
        logger.error("File not found in compilation database\n  ", input_file);
        return rval;
    } else {
        rval = SearchResult.init;
        rval.cflags = cflags ~ compile_commands[0].parseFlag;
        rval.absoluteFile = cast(string) compile_commands[0].absoluteFile;
    }

    return rval;
}

string toString(CompileCommandDB db) @safe pure {
    import std.algorithm : map, joiner;
    import std.conv : text;
    import std.format : format;
    import std.array;

    return db.payload.map!(a => format("%s\n  %s\n  %s\n  %s\n", a.directory,
            a.file, a.absoluteFile, a.command)).joiner().text;
}

string toString(CompileCommandSearch search) @safe pure {
    import std.algorithm : map, joiner;
    import std.conv : text;
    import std.format : format;
    import std.array;

    return search.payload.map!(a => format("%s\n  %s\n  %s\n  %s\n",
            a.directory, a.file, a.absoluteFile, a.command)).joiner().text;
}

/** Filter and normalize the compiler flags.
 *
 *  - Sanitize the compiler command by removing unnecessary flags.
 *    e.g those only for linking.
 *  - Remove excess white space.
 *  - Convert all filenames to absolute path.
 */
auto parseFlag(CompileCommand cmd) @safe pure {
    static auto filterPair(T)(ref T r, CompileCommand.Directory workdir) {
        enum State {
            Keep,
            Skip,
            IsInclude
        }

        import std.path : buildNormalizedPath, absolutePath;
        import std.array : appender;
        import std.range : ElementType;

        State st;
        auto rval = appender!(ElementType!T[]);

        foreach (arg; r) {
            if (st == State.Skip) {
                st = State.Keep;
            } else if (st == State.IsInclude) {
                st = State.Keep;
                // if an include flag make it absolute
                rval.put("-I");
                rval.put(buildNormalizedPath(cast(string) workdir, arg).absolutePath);
            } else if (arg.among("-o")) {
                st = State.Skip;
            }  // linker flags
            else if (arg.among("-l", "-L", "-z", "-u", "-T", "-Xlinker")) {
                st = State.Skip;
            }  // machine dependent flags
            // TODO investigate if it is a bad idea to remove -m flags that may affect int size etc
            else if (arg.among("-m")) {
                st = State.Skip;
            }  // machine dependent flags, AVR
            else if (arg.among("-nodevicelib", "-Waddr-space-convert")) {
                st = State.Skip;
            }  // machine dependent flags, VxWorks
            else if (arg.among("-non-static", "-Bstatic", "-Bdynamic",
                    "-Xbind-lazy", "-Xbind-now")) {
                st = State.Skip;
            }  // Preprocessor
            else if (arg.among("-MT", "-MQ", "-MF")) {
                st = State.Skip;
            }  // if an include flag make it absolute, as one argument by checking
            // length. 3 is to only match those that are -Ixyz
            else if (arg.length >= 3 && arg[0 .. 2] == "-I") {
                rval.put("-I");
                rval.put(buildNormalizedPath(cast(string) workdir, arg[2 .. $]).absolutePath);
            } else if (arg.among("-I")) {
                st = State.IsInclude;
            }  // parameter that seem to be filenames, remove
            else if (arg.length >= 1 && arg[0] != '-') {
                // skipping
            } else {
                rval.put(arg);
            }
        }

        return rval.data;
    }

    import std.algorithm : filter, among, splitter;
    import std.range : dropOne;

    // dfmt off
    auto pass1 = (cast(string) cmd.command).splitter(' ')
        .dropOne
        // remove empty strings
        .filter!(a => !(a == ""))
        // remove compile flag
        .filter!(a => !a.among("-c"))
        // machine dependent flags
        .filter!(a => !(a.length >= 3 && a[0 .. 2].among("-m")))
        // remove destination flag
        .filter!(a => !(a.length >= 3 && a[0 .. 2].among("-o")))
        // blacklist all -f, add to whitelist those that are compatible with clang
        .filter!(a => !(a.length >= 3 && a[0 .. 2].among("-f")))
        // linker flags
        .filter!(a => !a.among("-static", "-shared", "-rdynamic", "-s"))
        // a linker flag with filename as one argument, determined by checking length
        .filter!(a => !(a.length >= 3 && a[0 .. 2].among("-l", "-o")))
        // remove some of the preprocessor flags.
        .filter!(a => !a.among("-MD", "-MQ", "-MMD", "-MP", "-MG", "-E",
                "-cc1", "-S", "-M", "-MM", "-###"));
    // dfmt on

    return filterPair(pass1, cmd.directory);
}

@Name("Should be cflags with all unnecessary flags removed")
unittest {
    auto cmd = CompileCommand(CompileCommand.FileName("file1.cpp"),
            CompileCommand.AbsoluteFileName("/home/file1.cpp"), CompileCommand.Directory("/home"),
            CompileCommand.Command(`g++ -MD -lfoo.a -l bar.a -I bar -Igun -c a_filename.c`));

    auto s = cmd.parseFlag;
    s.shouldEqualPretty(["-I", "/home/bar", "-I", "/home/gun"]);
}

@Name("Should be cflags with some excess spacing")
unittest {
    auto cmd = CompileCommand(CompileCommand.FileName("file1.cpp"),
            CompileCommand.AbsoluteFileName("/home/file1.cpp"), CompileCommand.Directory("/home"),
            CompileCommand.Command(
                `g++           -MD     -lfoo.a -l bar.a       -I    bar     -Igun`));

    auto s = cmd.parseFlag;
    s.shouldEqualPretty(["-I", "/home/bar", "-I", "/home/gun"]);
}

@Name("Should be cflags with machine dependent removed")
unittest {
    auto cmd = CompileCommand(CompileCommand.FileName("file1.cpp"),
            CompileCommand.AbsoluteFileName("/home/file1.cpp"), CompileCommand.Directory("/home"),
            CompileCommand.Command(
                `g++ -mfoo -m bar -MD -lfoo.a -l bar.a -I bar -Igun -c a_filename.c`));

    auto s = cmd.parseFlag;
    s.shouldEqualPretty(["-I", "/home/bar", "-I", "/home/gun"]);
}

@Name("Should be cflags with all -f removed")
unittest {
    auto cmd = CompileCommand(CompileCommand.FileName("file1.cpp"),
            CompileCommand.AbsoluteFileName("/home/file1.cpp"), CompileCommand.Directory("/home"),
            CompileCommand.Command(
                `g++ -fmany-fooo -I bar -fno-fooo -Igun -flolol -c a_filename.c`));

    auto s = cmd.parseFlag;
    s.shouldEqualPretty(["-I", "/home/bar", "-I", "/home/gun"]);
}

version (unittest) {
    import std.file : getcwd;
    import std.path : absolutePath;
    import std.format : format;

    // contains a bit of extra junk that is expected to be removed
    immutable string dummy_path = "/path/to/../to/./db/compilation_db.json";
    immutable string dummy_dir = "/path/to/db";

    enum raw_dummy1 = `[
    {
        "directory": "dir1/dir2",
        "command": "g++ -Idir1 -c -o binary file1.cpp",
        "file": "file1.cpp"
    }
]`;

    enum raw_dummy2 = `[
    {
        "directory": "dir",
        "command": "g++ -Idir1 -c -o binary file1.cpp",
        "file": "file1.cpp"
    },
    {
        "directory": "dir",
        "command": "g++ -Idir1 -c -o binary file2.cpp",
        "file": "file2.cpp"
    }
]`;

    enum raw_dummy3 = `[
    {
        "directory": "dir1",
        "command": "g++ -Idir1 -c -o binary file3.cpp",
        "file": "file3.cpp"
    },
    {
        "directory": "dir2",
        "command": "g++ -Idir1 -c -o binary file3.cpp",
        "file": "file3.cpp"
    }
]`;
}

version (unittest) import std.array : appender;

@Name("Should be a compile command DB")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy1.parseCommands(CompileDbJsonPath(dummy_path), app);
    auto cmds = app.data;

    assert(cmds.length == 1);
    cmds[0].directory.shouldEqual(dummy_dir ~ "/dir1/dir2");
    cmds[0].command.shouldEqual("g++ -Idir1 -c -o binary file1.cpp");
    cmds[0].file.shouldEqual("file1.cpp");
    cmds[0].absoluteFile.shouldEqual(dummy_dir ~ "/dir1/dir2/file1.cpp");
}

@Name("Should be a DB with two entries")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy2.parseCommands(CompileDbJsonPath(dummy_path), app);
    auto cmds = app.data;

    assert(cmds.length == 2);
    cmds[0].file.shouldEqual("file1.cpp");
    cmds[1].file.shouldEqual("file2.cpp");
}

@Name("Should find filename")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy2.parseCommands(CompileDbJsonPath(dummy_path), app);
    auto cmds = CompileCommandDB(app.data);

    auto found = cmds.find(dummy_dir ~ "/dir/file2.cpp");
    assert(found.length == 1);
    found[0].file.shouldEqual("file2.cpp");
}

@Name("Should find no match by using an absolute path that doesn't exist in DB")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy2.parseCommands(CompileDbJsonPath(dummy_path), app);
    auto cmds = CompileCommandDB(app.data);

    auto found = cmds.find("./file2.cpp");
    assert(found.length == 0);
}

@Name("Should find one match by using the absolute filename to disambiguous")
unittest {
    import unit_threaded : writelnUt;

    auto app = appender!(CompileCommand[])();
    raw_dummy3.parseCommands(CompileDbJsonPath(dummy_path), app);
    auto cmds = CompileCommandDB(app.data);

    auto found = cmds.find(dummy_dir ~ "/dir2/file3.cpp");
    assert(found.length == 1);

    found.toString.shouldEqualPretty(format("%s/dir2
  file3.cpp
  %s/dir2/file3.cpp
  g++ -Idir1 -c -o binary file3.cpp
", dummy_dir, dummy_dir));
}

@Name("Should be a pretty printed search result")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy2.parseCommands(CompileDbJsonPath(dummy_path), app);
    auto cmds = CompileCommandDB(app.data);
    auto found = cmds.find(dummy_dir ~ "/dir/file2.cpp");

    found.toString.shouldEqualPretty(format("%s/dir
  file2.cpp
  %s/dir/file2.cpp
  g++ -Idir1 -c -o binary file2.cpp
", dummy_dir, dummy_dir));
}

@Name("Should be a compile command DB with relative path")
unittest {
    enum raw = `[
    {
        "directory": ".",
        "command": "g++ -Idir1 -c -o binary file1.cpp",
        "file": "file1.cpp"
    }
    ]`;
    auto app = appender!(CompileCommand[])();
    raw.parseCommands(CompileDbJsonPath(dummy_path), app);
    auto cmds = app.data;

    assert(cmds.length == 1);
    cmds[0].directory.shouldEqual(dummy_dir);
    cmds[0].file.shouldEqual("file1.cpp");
    cmds[0].absoluteFile.shouldEqual(dummy_dir ~ "/file1.cpp");
}
