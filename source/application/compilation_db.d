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

import std.typecons : Nullable, Typedef;
import logger = std.experimental.logger;

import application.types;

version (unittest) {
    import unit_threaded : Name, shouldEqual;
    import test.helpers : shouldEqualPretty;
} else {
    struct Name {
        string name_;
    }
}

/// Hold an entry from the compilation database
struct CompileCommand {
    alias FileName = Typedef!(string, string.init, "FileName");
    alias AbsoluteFileName = Typedef!(string, string.init, "AbsoluteFileName");
    alias Directory = Typedef!(string, string.init, "WorkDir");
    alias Command = Typedef!(string, string.init, "Command");

    FileName file;
    AbsoluteFileName absoluteFile;
    Directory directory;
    Command command;
}

alias CompileDbJsonPath = Typedef!(string, string.init, "CompileDbJsonPath");
alias CompileCommandDB = Typedef!(CompileCommand[], null, "CompileCommandDB");
// The result of searching for a file in a compilation DB.
// The file may be occur more than one time therefor an array.
alias CompileCommandSearch = Typedef!(CompileCommand[], null, "CompileCommandSearch");

private void parseCommands(T)(string raw_input, ref T out_range) nothrow {
    import std.json;

    static Nullable!CompileCommand toCompileCommand(JSONValue v) nothrow {
        import std.path : buildNormalizedPath, absolutePath;
        import logger = cpptooling.utility.logger;

        // expects that v is a tuple of 3 json values with the keys
        // directory, command, file

        Nullable!CompileCommand rval;

        try {
            string abs_file = buildNormalizedPath(buildNormalizedPath(v["directory"].str,
                    v["file"].str).absolutePath);
            auto tmp = CompileCommand(CompileCommand.FileName(v["file"].str),
                    CompileCommand.AbsoluteFileName(abs_file), CompileCommand.Directory(v["directory"].str),
                    CompileCommand.Command(v["command"].str));
            rval = tmp;
        }
        catch (Exception ex) {
            logger.error("Unable to parse json attribute: " ~ ex.msg);
        }

        return rval;
    }

    static void put(T)(JSONValue v, ref T out_range) nothrow {
        import std.algorithm : map, filter;
        import std.array : array;
        import logger = cpptooling.utility.logger;

        try {
            // dfmt off
            foreach (e; v.array()
                     // map the JSON tuples to D structs
                     .map!(a => toCompileCommand(a))
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
        put(json, out_range);
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
    raw.parseCommands(app);
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
 * Separated search and reduce to optimize and simplify implementation.
 * The find can be kept nothrow, nogc and only applied in those cases of >1
 * match.
 *
 * When searching for the compile command for a file, the compilation db can
 * return several commands, as the file may have been compiled with different
 * options in different places of the project.
 *
 * Params:
 *  abs_filename = absolute filename to use as key when searching in the db
 */
CompileCommandSearch find(CompileCommandDB db, string abs_filename) @safe /*pure nothrow @nogc*/ {
    import std.algorithm : find;
    import std.range : takeOne;

    auto found = find!((a, b) => (a.absoluteFile.length == b.length && a.absoluteFile == b))(
            cast(CompileCommand[]) db, abs_filename).takeOne;

    return CompileCommandSearch(found);
}

/** Append the compiler flags if a match is found in the DB or error out.
 */
Nullable!(string[]) appendOrError(CompileCommandDB compile_db, in string[] cflags,
        in string input_file) @safe {
    import application.compilation_db : find, toString;

    auto compile_commands = compile_db.find(input_file);
    debug {
        logger.trace(compile_commands.length > 0,
                "CompilationDatabase match (by filename):\n", compile_commands.toString);
    }

    typeof(return) rval;
    if (compile_commands.length == 0) {
        logger.error("File not found in compilation database\n  ", input_file);
        return rval;
    } else {
        rval = cflags ~ compile_commands[0].parseFlag;
    }

    return rval;
}

string toString(CompileCommandDB db) @safe pure {
    import std.algorithm : map, joiner;
    import std.conv : text;
    import std.format : format;
    import std.array;
    import std.typecons : TypedefType;

    return (cast(TypedefType!CompileCommandDB) db).map!(a => format("%s\n  %s\n  %s\n  %s\n",
            cast(string) a.directory, cast(string) a.file,
            cast(string) a.absoluteFile, cast(string) a.command)).joiner().text;
}

string toString(CompileCommandSearch search) @safe pure {
    import std.algorithm : map, joiner;
    import std.conv : text;
    import std.format : format;
    import std.array;
    import std.typecons : TypedefType;

    return (cast(TypedefType!CompileCommandSearch) search).map!(a => format("%s\n  %s\n  %s\n  %s\n",
            cast(string) a.directory, cast(string) a.file,
            cast(string) a.absoluteFile, cast(string) a.command)).joiner().text;
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
    raw_dummy1.parseCommands(app);
    auto cmds = app.data;

    assert(cmds.length == 1);
    cmds[0].directory.shouldEqual("dir1/dir2");
    cmds[0].command.shouldEqual("g++ -Idir1 -c -o binary file1.cpp");
    cmds[0].file.shouldEqual("file1.cpp");
    cmds[0].absoluteFile.shouldEqual("dir1/dir2/file1.cpp".absolutePath);
}

@Name("Should be a DB with two entries")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy2.parseCommands(app);
    auto cmds = app.data;

    assert(cmds.length == 2);
    cmds[0].file.shouldEqual("file1.cpp");
    cmds[1].file.shouldEqual("file2.cpp");
}

@Name("Should find filename")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy2.parseCommands(app);
    auto cmds = CompileCommandDB(app.data);

    auto found = cmds.find("dir/file2.cpp".absolutePath);
    assert(found.length == 1);
    found[0].file.shouldEqual("file2.cpp");
}

@Name("Should find no match by using an absolute path that doesn't exist in DB")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy2.parseCommands(app);
    auto cmds = CompileCommandDB(app.data);

    auto found = cmds.find("./file2.cpp");
    assert(found.length == 0);
}

@Name("Should find one match by using the absolute filename to disambiguous")
unittest {
    import unit_threaded : writelnUt;

    auto app = appender!(CompileCommand[])();
    raw_dummy3.parseCommands(app);
    auto cmds = CompileCommandDB(app.data);

    auto found = cmds.find("dir2/file3.cpp".absolutePath);
    assert(found.length == 1);

    found.toString.shouldEqualPretty(format("dir2
  file3.cpp
  %s/dir2/file3.cpp
  g++ -Idir1 -c -o binary file3.cpp
", getcwd));
}

@Name("Should be a pretty printed search result")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy2.parseCommands(app);
    auto cmds = CompileCommandDB(app.data);
    auto found = cmds.find("dir/file2.cpp".absolutePath);

    found.toString.shouldEqualPretty(format("dir
  file2.cpp
  %s/dir/file2.cpp
  g++ -Idir1 -c -o binary file2.cpp
", getcwd));
}
