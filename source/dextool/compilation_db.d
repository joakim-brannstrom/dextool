/**
Copyright: Copyright (c) 2016-2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Utility functions for Clang Compilation Databases.
*/
module dextool.compilation_db;

import std.json : JSONValue;
import std.typecons : Nullable;
import logger = std.experimental.logger;

version (unittest) {
    import unit_threaded : Name, shouldEqual;
    import test.extra_should : shouldEqualPretty;
}

/** Hold an entry from the compilation database.
 *
 * The following information is from the official specification.
 * $(LINK2 http://clang.llvm.org/docs/JSONCompilationDatabase.html, Standard)
 *
 * directory: The working directory of the compilation. All paths specified in
 * the command or file fields must be either absolute or relative to this
 * directory.
 *
 * file: The main translation unit source processed by this compilation step.
 * This is used by tools as the key into the compilation database. There can be
 * multiple command objects for the same file, for example if the same source
 * file is compiled with different configurations.
 *
 * command: The compile command executed. After JSON unescaping, this must be a
 * valid command to rerun the exact compilation step for the translation unit
 * in the environment the build system uses. Parameters use shell quoting and
 * shell escaping of quotes, with ‘"‘ and ‘\‘ being the only special
 * characters. Shell expansion is not supported.
 *
 * Dextool additions.
 * The standard do not specify how to treat "directory" when it is a relative
 * path. The logic chosen in dextool is to treat it as relative to the path
 * the compilation database file is read from.
 */
@safe struct CompileCommand {
    /// The raw filename from the tuples "file" value.
    static struct FileName {
        string payload;
        alias payload this;
    }

    /// The combination of the tuples "file" and "directory" value.
    static struct AbsoluteFileName {
        string payload;
        alias payload this;

        invariant {
            import std.path : isAbsolute;

            assert(payload.isAbsolute);
        }

        this(AbsoluteDirectory work_dir, string raw_path) {
            import std.path : buildNormalizedPath, absolutePath;

            payload = buildNormalizedPath(work_dir, raw_path).absolutePath;
        }
    }

    /// The tuples "directory" value converted to the absolute path.
    static struct AbsoluteDirectory {
        string payload;
        alias payload this;

        invariant {
            import std.path : isAbsolute;

            assert(payload.isAbsolute);
        }

        this(AbsoluteCompileDbDirectory db_path, string raw_path) {
            import std.path : buildNormalizedPath, absolutePath;

            payload = buildNormalizedPath(db_path, raw_path).absolutePath;
        }
    }

    /// The raw command from the tuples "command" value.
    static struct Command {
        string payload;
        alias payload this;
    }

    ///
    FileName file;
    ///
    AbsoluteFileName absoluteFile;
    ///
    AbsoluteDirectory directory;
    ///
    Command command;
}

/// The path to the compilation database.
struct CompileDbFile {
    string payload;
    alias payload this;
}

/// The absolute path to the directory the compilation database reside at.
struct AbsoluteCompileDbDirectory {
    string payload;
    alias payload this;

    invariant {
        import std.path : isAbsolute;

        assert(payload.isAbsolute);
    }

    this(string file_path) {
        import std.path : buildNormalizedPath, dirName, absolutePath;

        payload = buildNormalizedPath(file_path).absolutePath.dirName;
    }

    this(CompileDbFile db) {
        this(cast(string) db);
    }

    unittest {
        import std.path;

        auto dir = AbsoluteCompileDbDirectory(".");
        assert(dir.isAbsolute);
    }
}

/// A complete compilation database.
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

string[] getHeaderFiles(CompileCommandDB compile_db)
{
    import std.algorithm: canFind, filter, each;
    import std.range : chain;
    import std.file : dirEntries, SpanMode;
    import std.array : appender;
    import std.stdio;

    auto rval = appender!(string[])();
    auto directories = new string[0];
    foreach (cmd ; compile_db)
    {
         auto flags = parseFlag(cmd, CompileCommandFilter());
         flags.filter!(a => a[0] != '-' && !directories.canFind(a))
            .each!(dir => (dirEntries(dir, "*_factory.{h,hpp}", SpanMode.depth))
                .each!(file => rval.put(file)));
        
        directories ~= flags;
    }

    return rval.data;
}

private Nullable!CompileCommand toCompileCommand(JSONValue v, AbsoluteCompileDbDirectory db_dir) nothrow {
    import std.algorithm : map, filter;
    import std.json : JSON_TYPE;
    import std.range : only;

    try {
        const auto directory = v["directory"];
        const auto file = v["file"];
        const auto command = v["command"];

        foreach (a; only(directory, file, command).map!(a => !a.isNull
                && a.type == JSON_TYPE.STRING).filter!(a => !a)) {
            // sanity check.
            // if any element is false then break early.
            return typeof(return)();
        }

        return toCompileCommand(directory.str, file.str, command.str, db_dir);
    }
    catch (Exception ex) {
        import dextool.logger : error;

        error("Unable to parse json attribute: " ~ ex.msg);
    }

    return typeof(return)();
}

/** Transform a json entry to a CompileCommand.
 *
 * This function is under no circumstances meant to be exposed outside this module.
 * The API is badly designed for common use because it relies on the position
 * order of the strings for their meaning.
 */
private Nullable!CompileCommand toCompileCommand(string directory, string file,
        string command, AbsoluteCompileDbDirectory db_dir) nothrow {
    // expects that v is a tuple of 3 json values with the keys directory,
    // command, file

    Nullable!CompileCommand rval;

    try {
        auto abs_workdir = CompileCommand.AbsoluteDirectory(db_dir, directory);
        auto abs_file = CompileCommand.AbsoluteFileName(abs_workdir, file);
        auto tmp = CompileCommand(CompileCommand.FileName(file), abs_file,
                abs_workdir, CompileCommand.Command(command));
        rval = tmp;
    }
    catch (Exception ex) {
        import dextool.logger : error;

        error("Unable to parse json attribute: " ~ ex.msg);
    }

    return rval;
}

/** Parse a CompilationDatabase.
 *
 * Params:
 *  raw_input = the content of the CompilationDatabase.
 *  in_file = path to the compilation database file.
 *  out_range = range to write the output to.
 */
private void parseCommands(T)(string raw_input, CompileDbFile in_file, ref T out_range) nothrow {
    import std.json : parseJSON, JSONException;

    static void put(T)(JSONValue v, AbsoluteCompileDbDirectory dbdir, ref T out_range) nothrow {
        import std.algorithm : map, filter;
        import std.array : array;
        import logger = dextool.logger;

        try {
            // dfmt off
            foreach (e; v.array()
                     // map the JSON tuples to D structs
                     .map!(a => toCompileCommand(a, dbdir))
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
        auto as_dir = AbsoluteCompileDbDirectory(in_file);
        put(json, as_dir, out_range);
    }
    catch (JSONException ex) {
        import dextool.logger : error;

        error("Error while parsing compilation database: " ~ ex.msg);
    }
    catch (Exception ex) {
        import dextool.logger : error;

        error("Error while parsing compilation database: " ~ ex.msg);
    }
}

void fromFile(T)(CompileDbFile filename, ref T app) {
    import std.algorithm : joiner;
    import std.conv : text;
    import std.stdio : File;

    auto raw = File(cast(string) filename).byLineCopy.joiner.text;
    raw.parseCommands(filename, app);
}

void fromFiles(T)(CompileDbFile[] fnames, ref T app) {
    foreach (f; fnames) {
        f.fromFile(app);
    }
}

/** Return default path if argument is null.
 */
CompileDbFile[] orDefaultDb(string[] cli_path) @safe pure nothrow {
    import std.array : array;
    import std.algorithm : map;

    if (cli_path is null) {
        return [CompileDbFile("compile_commands.json")];
    }

    return cli_path.map!(a => CompileDbFile(a)).array();
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
    import dextool.logger;

    debug trace("Looking for " ~ (filename.isAbsolute ? "absolute" : "relative") ~ " " ~ filename);
}
out (result) {
    import std.conv : to;
    import dextool.logger;

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

private struct SearchResult {
    string[] cflags;
    string absoluteFile;
}

/** Append the compiler flags if a match is found in the DB or error out.
 */
Nullable!(SearchResult) appendOrError(CompileCommandDB compile_db,
        const string[] cflags, const string input_file) @safe {

    return appendOrError(compile_db, cflags, input_file, defaultCompilerFilter);
}

/** Append the compiler flags if a match is found in the DB or error out.
 */
Nullable!(SearchResult) appendOrError(CompileCommandDB compile_db,
        const string[] cflags, const string input_file, const CompileCommandFilter flag_filter) @safe {
    auto compile_commands = compile_db.find(input_file.idup);
    debug {
        logger.trace(compile_commands.length > 0,
                "CompilationDatabase match (by filename):\n", compile_commands.toString);
        if (compile_commands.length == 0) {
            logger.trace(compile_db.toString);
        }

        logger.tracef("CompilationDatabase filter: %s", flag_filter);
    }

    typeof(return) rval;
    if (compile_commands.length == 0) {
        logger.error("File not found in compilation database\n  ", input_file);
        return rval;
    } else {
        rval = SearchResult.init;
        rval.cflags = cflags ~ compile_commands[0].parseFlag(flag_filter);
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

const auto defaultCompilerFilter = CompileCommandFilter(defaultCompilerFlagFilter, 1);

/// Returns: array of default flags to exclude.
auto defaultCompilerFlagFilter() @safe {
    import dextool.type : FilterClangFlag;
    import std.array : appender;

    auto app = appender!(FilterClangFlag[])();

    // dfmt off
    foreach (f; [
             // allow warnings. too much difference between gcc and clang to be
             // of use.
             "-Werror",
             // remove basic compile flag irrelevant for AST generation
             "-c", "-o",
             // machine dependent flags
             "-m",
             // machine dependent flags, AVR
             "-nodevicelib", "-Waddr-space-convert",
             // machine dependent flags, VxWorks
             "-non-static", "-Bstatic", "-Bdynamic", "-Xbind-lazy", "-Xbind-now",
             // blacklist all -f, add to whitelist those that are compatible with clang
             "-f",
             // linker flags
             "-static", "-shared", "-rdynamic", "-s", "-l", "-L", "-z", "-u", "-T", "-Xlinker",
             // a linker flag with filename as one argument, determined by checking length
             "-l",
             // remove some of the preprocessor flags.
             "-MT", "-MF", "-MD", "-MQ", "-MMD", "-MP", "-MG", "-E", "-cc1", "-S", "-M", "-MM", "-###",
             ]) {
        app.put(FilterClangFlag(f));
    }
    // dfmt on

    return app.data;
}

struct CompileCommandFilter {
    import dextool.type : FilterClangFlag;

    FilterClangFlag[] filter;
    int skipCompilerArgs = 1;
}

/** Filter and normalize the compiler flags.
 *
 *  - Sanitize the compiler command by removing flags matching the filter.
 *  - Remove excess white space.
 *  - Convert all filenames to absolute path.
 */
string[] parseFlag(CompileCommand cmd, const CompileCommandFilter flag_filter) @safe {
    import dextool.type : FilterClangFlag;

    static bool excludeStartWith(string flag, const FilterClangFlag[] flag_filter) @safe {
        import std.algorithm : startsWith, filter, count;

        // the purpuse is to find if any of the flags in flag_filter matches
        // the start of flag.

        // dfmt off
        return 0 != flag_filter
            .filter!(a => a.kind == FilterClangFlag.Kind.exclude)
            // keep flags that are at least the length of values
            .filter!(a => flag.length >= a.length)
            // if the flag starst with the exclude-flag it is a match
            .filter!(a => flag.startsWith(a.payload))
            .count();
        // dfmt on
    }

    static bool isCombindedIncludeFlag(string flag) @safe {
        // if an include flag make it absolute, as one argument by checking
        // length. 3 is to only match those that are -Ixyz
        return flag.length >= 3 && flag[0 .. 2] == "-I";
    }

    static bool isNotAFlag(string flag) @safe {
        // good enough if it seem to be a file
        return flag.length >= 1 && flag[0] != '-';
    }

    static auto filterPair(T)(ref T r, CompileCommand.AbsoluteDirectory workdir,
            const FilterClangFlag[] flag_filter) @safe {
        enum State {
            keep,
            skip,
            skipIfNotFlag,
            isInclude
        }

        import std.path : buildNormalizedPath, absolutePath;
        import std.array : appender;
        import std.range : ElementType;

        State st;
        auto rval = appender!(ElementType!T[]);

        foreach (arg; r) {
            if (st == State.skip) {
                st = State.keep;
            } else if (st == State.skipIfNotFlag && isNotAFlag(arg)) {
                st = State.keep;
            } else if (st == State.isInclude) {
                st = State.keep;
                // if an include flag make it absolute
                rval.put("-I");
                rval.put(buildNormalizedPath(workdir, arg).absolutePath);
            } else if (isCombindedIncludeFlag(arg)) {
                rval.put("-I");
                rval.put(buildNormalizedPath(workdir, arg[2 .. $]).absolutePath);
            } else if (arg.among("-I")) {
                st = State.isInclude;
            }  // parameter that seem to be filenames, remove
            else if (excludeStartWith(arg, flag_filter)) {
                st = State.skipIfNotFlag;
            } else if (isNotAFlag(arg)) {
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
        // remove empty strings
        .filter!(a => !(a == ""));
    // dfmt on

    // consume elements
    foreach (_; 0 .. flag_filter.skipCompilerArgs) {
        if (!pass1.empty) {
            pass1.popFront;
        }
    }

    return filterPair(pass1, cmd.directory, flag_filter.filter);
}

@("Should be cflags with all unnecessary flags removed")
unittest {
    auto cmd = toCompileCommand("/home", "file1.cpp",
            `g++ -MD -lfoo.a -l bar.a -I bar -Igun -c a_filename.c`,
            AbsoluteCompileDbDirectory("/home"));
    auto s = cmd.parseFlag(defaultCompilerFilter);
    s.shouldEqualPretty(["-I", "/home/bar", "-I", "/home/gun"]);
}

@("Should be cflags with some excess spacing")
unittest {
    auto cmd = toCompileCommand("/home", "file1.cpp",
            `g++           -MD     -lfoo.a -l bar.a       -I    bar     -Igun`,
            AbsoluteCompileDbDirectory("/home"));

    auto s = cmd.parseFlag(defaultCompilerFilter);
    s.shouldEqualPretty(["-I", "/home/bar", "-I", "/home/gun"]);
}

@("Should be cflags with machine dependent removed")
unittest {
    auto cmd = toCompileCommand("/home", "file1.cpp",
            `g++ -mfoo -m bar -MD -lfoo.a -l bar.a -I bar -Igun -c a_filename.c`,
            AbsoluteCompileDbDirectory("/home"));

    auto s = cmd.parseFlag(defaultCompilerFilter);
    s.shouldEqualPretty(["-I", "/home/bar", "-I", "/home/gun"]);
}

@("Should be cflags with all -f removed")
unittest {
    auto cmd = toCompileCommand("/home", "file1.cpp",
            `g++ -fmany-fooo -I bar -fno-fooo -Igun -flolol -c a_filename.c`,
            AbsoluteCompileDbDirectory("/home"));

    auto s = cmd.parseFlag(defaultCompilerFilter);
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

version (unittest) {
    import std.array : appender;
    import unit_threaded : writelnUt;
}

@("Should be a compile command DB")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy1.parseCommands(CompileDbFile(dummy_path), app);
    auto cmds = app.data;

    assert(cmds.length == 1);
    cmds[0].directory.shouldEqual(dummy_dir ~ "/dir1/dir2");
    cmds[0].command.shouldEqual("g++ -Idir1 -c -o binary file1.cpp");
    cmds[0].file.shouldEqual("file1.cpp");
    cmds[0].absoluteFile.shouldEqual(dummy_dir ~ "/dir1/dir2/file1.cpp");
}

@("Should be a DB with two entries")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy2.parseCommands(CompileDbFile(dummy_path), app);
    auto cmds = app.data;

    cmds[0].file.shouldEqual("file1.cpp");
    cmds[1].file.shouldEqual("file2.cpp");
}

@("Should find filename")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy2.parseCommands(CompileDbFile(dummy_path), app);
    auto cmds = CompileCommandDB(app.data);

    auto found = cmds.find(dummy_dir ~ "/dir/file2.cpp");
    assert(found.length == 1);
    found[0].file.shouldEqual("file2.cpp");
}

@("Should find no match by using an absolute path that doesn't exist in DB")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy2.parseCommands(CompileDbFile(dummy_path), app);
    auto cmds = CompileCommandDB(app.data);

    auto found = cmds.find("./file2.cpp");
    assert(found.length == 0);
}

@("Should find one match by using the absolute filename to disambiguous")
unittest {
    import unit_threaded : writelnUt;

    auto app = appender!(CompileCommand[])();
    raw_dummy3.parseCommands(CompileDbFile(dummy_path), app);
    auto cmds = CompileCommandDB(app.data);

    auto found = cmds.find(dummy_dir ~ "/dir2/file3.cpp");
    assert(found.length == 1);

    found.toString.shouldEqualPretty(format("%s/dir2
  file3.cpp
  %s/dir2/file3.cpp
  g++ -Idir1 -c -o binary file3.cpp
", dummy_dir, dummy_dir));
}

@("Should be a pretty printed search result")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy2.parseCommands(CompileDbFile(dummy_path), app);
    auto cmds = CompileCommandDB(app.data);
    auto found = cmds.find(dummy_dir ~ "/dir/file2.cpp");

    found.toString.shouldEqualPretty(format("%s/dir
  file2.cpp
  %s/dir/file2.cpp
  g++ -Idir1 -c -o binary file2.cpp
", dummy_dir, dummy_dir));
}

@("Should be a compile command DB with relative path")
unittest {
    enum raw = `[
    {
        "directory": ".",
        "command": "g++ -Idir1 -c -o binary file1.cpp",
        "file": "file1.cpp"
    }
    ]`;
    auto app = appender!(CompileCommand[])();
    raw.parseCommands(CompileDbFile(dummy_path), app);
    auto cmds = app.data;

    assert(cmds.length == 1);
    cmds[0].directory.shouldEqual(dummy_dir);
    cmds[0].file.shouldEqual("file1.cpp");
    cmds[0].absoluteFile.shouldEqual(dummy_dir ~ "/file1.cpp");
}

@("Should be a DB read from a relative path with the contained paths adjusted appropriately")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy3.parseCommands(CompileDbFile("path/compile_db.json"), app);
    auto cmds = CompileCommandDB(app.data);

    auto abs_path = getcwd() ~ "/path";

    auto found = cmds.find(abs_path ~ "/dir2/file3.cpp");
    assert(found.length == 1);

    found.toString.shouldEqualPretty(format("%s/dir2
  file3.cpp
  %s/dir2/file3.cpp
  g++ -Idir1 -c -o binary file3.cpp
", abs_path, abs_path));
}
