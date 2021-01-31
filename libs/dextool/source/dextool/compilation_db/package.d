/**
Copyright: Copyright (c) 2016-2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Utility functions for Clang Compilation Databases.

# Usage
Call the function `fromArgCompileDb` to create one, merged database.

Extract flags the flags for a file by calling `appendOrError`.

Example:
---
auto dbs = fromArgCompileDb(["foo.json]);
auto flags = dbs.appendOrError(dbs, null, "foo.cpp", defaultCompilerFlagFilter);
---
*/
module dextool.compilation_db;

import logger = std.experimental.logger;
import std.algorithm : map, filter, splitter, joiner;
import std.array : empty, array, appender;
import std.exception : collectException;
import std.json : JSONValue;
import std.path : buildPath;
import std.typecons : Nullable;

import dextool.type : AbsolutePath, Path;

public import dextool.compilation_db.user_filerange;
public import dextool.compilation_db.system_compiler : deduceSystemIncludes,
    SystemIncludePath, Compiler;

version (unittest) {
    import std.path : buildPath;
    import unit_threaded : shouldEqual;
}

@safe:

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
 * argumets: The compile command executed as list of strings. Either arguments
 * or command is required.
 *
 * output: The name of the output created by this compilation step. This field
 * is optional. It can be used to distinguish different processing modes of the
 * same input file.
 *
 * Dextool additions.
 * The standard do not specify how to treat "directory" when it is a relative
 * path. The logic chosen in dextool is to treat it as relative to the path
 * the compilation database file is read from.
 */
struct CompileCommand {
    import dextool.type : Path, AbsolutePath;

    /// The raw command from the tuples "command" or "arguments value.
    static struct Command {
        string[] payload;
        alias payload this;
        bool hasValue() @safe pure nothrow const @nogc {
            return payload.length != 0;
        }
    }

    /// File that where compiled.
    Path file;
    /// ditto.
    AbsolutePath absoluteFile;
    /// Working directory of the command that compiled the input.
    AbsolutePath directory;
    /// The executing command when compiling.
    Command command;
    /// The resulting object file.
    Path output;
    /// ditto.
    AbsolutePath absoluteOutput;
}

/// The path to the compilation database.
struct CompileDbFile {
    Path payload;
    alias payload this;

    this(string p) @safe nothrow {
        payload = Path(p);
    }
}

/// The absolute path to the directory the compilation database reside at.
struct AbsoluteCompileDbDirectory {
    AbsolutePath payload;
    alias payload this;

    this(Path path) {
        import std.path : dirName;

        payload = AbsolutePath(path.dirName.Path);
    }
}

/// A complete compilation database.
struct CompileCommandDB {
    CompileCommand[] payload;
    alias payload this;

    bool empty() @safe pure nothrow const @nogc {
        return payload.empty;
    }
}

// The result of searching for a file in a compilation DB.
// The file may be occur more than one time therefor an array.
struct CompileCommandSearch {
    CompileCommand[] payload;
    alias payload this;

    bool empty() @safe pure nothrow const @nogc {
        return payload.empty;
    }
}

/**
 * Trusted: opIndex for JSONValue is @safe in DMD-2.077.0
 * remove the trusted attribute when the minimal requirement is upgraded.
 */
private Nullable!CompileCommand toCompileCommand(JSONValue v, AbsoluteCompileDbDirectory db_dir) nothrow @trusted {
    import std.exception : assumeUnique;
    import std.range : only;
    import std.utf : byUTF;

    static if (__VERSION__ < 2085L) {
        import std.json : JSON_TYPE;

        alias JSONType = JSON_TYPE;
        alias JSONType_array = JSON_TYPE.ARRAY;
        alias JSONType_string = JSON_TYPE.STRING;
    } else {
        import std.json : JSONType;

        alias JSONType_array = JSONType.array;
        alias JSONType_string = JSONType.string;
    }

    string[] command = () {
        string[] cmd;
        try {
            cmd = v["command"].str.splitter.filter!(a => a.length != 0).array;
        } catch (Exception ex) {
        }

        // prefer command over arguments if both are present because of bugs in
        // tools that produce compile_commands.json.
        if (cmd.length != 0)
            return cmd;

        try {
            enum j_arg = "arguments";
            const auto j_type = v[j_arg].type;
            if (j_type == JSONType_string)
                cmd = v[j_arg].str.splitter.filter!(a => a.length != 0).array;
            else if (j_type == JSONType_array) {
                import std.range;

                cmd = v[j_arg].arrayNoRef
                    .filter!(a => a.type == JSONType_string)
                    .map!(a => a.str)
                    .filter!(a => a.length != 0)
                    .array;
            }
        } catch (Exception ex) {
        }

        return cmd;
    }();

    if (command.length == 0) {
        logger.error("Unable to parse the JSON tuple. Both command and arguments are empty")
            .collectException;
        return typeof(return)();
    }

    string output;
    try {
        output = v["output"].str;
    } catch (Exception ex) {
    }

    try {
        const directory = v["directory"];
        const file = v["file"];

        foreach (a; only(directory, file).map!(a => !a.isNull && a.type == JSONType_string)
                .filter!(a => !a)) {
            // sanity check.
            // if any element is false then break early.
            return typeof(return)();
        }

        return toCompileCommand(directory.str, file.str, command, db_dir, output);
    } catch (Exception e) {
        logger.info("Input JSON: ", v.toPrettyString).collectException;
        logger.error("Unable to parse json: ", e.msg).collectException;
    }

    return typeof(return)();
}

/** Transform a json entry to a CompileCommand.
 *
 * This function is under no circumstances meant to be exposed outside this module.
 * The API is badly designed for common use because it relies on the position
 * order of the strings for their meaning.
 */
Nullable!CompileCommand toCompileCommand(string directory, string file,
        string[] command, AbsoluteCompileDbDirectory db_dir, string output) nothrow {
    // expects that v is a tuple of 3 json values with the keys directory,
    // command, file

    Nullable!CompileCommand rval;

    try {
        auto abs_workdir = AbsolutePath(buildPath(db_dir, directory.Path));
        auto abs_file = AbsolutePath(buildPath(abs_workdir, file.Path));
        auto abs_output = AbsolutePath(buildPath(abs_workdir, output.Path));
        // dfmt off
        rval = CompileCommand(
            Path(file),
            abs_file,
            abs_workdir,
            CompileCommand.Command(command),
            Path(output),
            abs_output);
        // dfmt on
    } catch (Exception ex) {
        logger.error("Unable to parse json: ", ex.msg).collectException;
    }

    return rval;
}

/** Parse a CompilationDatabase.
 *
 * Params:
 *  raw_input = the content of the CompilationDatabase.
 *  db = path to the compilation database file.
 *  out_range = range to write the output to.
 */
private void parseCommands(T)(string raw_input, CompileDbFile db, ref T out_range) nothrow {
    import std.json : parseJSON, JSONException;

    static void put(T)(JSONValue v, AbsoluteCompileDbDirectory dbdir, ref T out_range) nothrow {

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
        } catch (Exception ex) {
            logger.error("Unable to parse json:", ex.msg).collectException;
        }
    }

    try {
        // trusted: is@safe in DMD-2.077.0
        // remove the trusted attribute when the minimal requirement is upgraded.
        auto json = () @trusted { return parseJSON(raw_input); }();
        auto as_dir = AbsoluteCompileDbDirectory(db.AbsolutePath);

        // trusted: this function is private so the only user of it is this module.
        // the only problem would be in the out_range. It is assumed that the
        // out_range takes care of the validation and other security aspects.
        () @trusted { put(json, as_dir, out_range); }();
    } catch (Exception ex) {
        logger.error("Error while parsing compilation database: " ~ ex.msg).collectException;
    }
}

void fromFile(T)(CompileDbFile filename, ref T app) {
    import std.file : readText;

    auto raw = readText(filename);
    if (raw.length == 0)
        logger.warning("File is empty: ", filename);

    raw.parseCommands(filename, app);
}

void fromFiles(T)(CompileDbFile[] fnames, ref T app) {
    import std.file : exists;

    foreach (f; fnames) {
        if (!exists(f))
            throw new Exception("File do not exist: " ~ f);
        f.fromFile(app);
    }
}

/** Return default path if argument is null.
 */
CompileDbFile[] orDefaultDb(string[] cli_path) @safe nothrow {
    if (cli_path.length == 0) {
        return [CompileDbFile("compile_commands.json")];
    }

    return cli_path.map!(a => CompileDbFile(a)).array();
}

/** Find a best matching compile_command in the database against the path
 * pattern `glob`.
 *
 * When searching for the compile command for a file, the compilation db can
 * return several commands, as the file may have been compiled with different
 * options in different parts of the project.
 *
 * Params:
 *  glob = glob pattern to find a matching file in the DB against
 */
CompileCommandSearch find(CompileCommandDB db, string glob) @safe {
    foreach (a; db.filter!(a => isMatch(a, glob))) {
        return CompileCommandSearch([a]);
    }
    return CompileCommandSearch.init;
}

/** Check if `glob` fuzzy matches `a`.
 */
bool isMatch(CompileCommand a, string glob) {
    import std.path : globMatch;

    if (a.absoluteFile == glob)
        return true;
    else if (a.absoluteFile == AbsolutePath(glob))
        return true;
    else if (a.file == glob)
        return true;
    else if (globMatch(a.absoluteFile, glob))
        return true;
    else if (a.absoluteOutput == glob)
        return true;
    else if (a.output == glob)
        return true;
    else if (globMatch(a.absoluteOutput, glob))
        return true;
    return false;
}

string toString(CompileCommand[] db) @safe pure {
    import std.conv : text;
    import std.format : formattedWrite;

    auto app = appender!string();

    foreach (a; db) {
        formattedWrite(app, "%s\n  %s\n  %s\n", a.directory, a.file, a.absoluteFile);

        if (!a.output.empty) {
            formattedWrite(app, "  %s\n", a.output);
            formattedWrite(app, "  %s\n", a.absoluteOutput);
        }

        if (!a.command.empty)
            formattedWrite(app, "  %-(%s %)\n", a.command);
    }

    return app.data;
}

string toString(CompileCommandDB db) @safe pure {
    return toString(db.payload);
}

string toString(CompileCommandSearch search) @safe pure {
    return toString(search.payload);
}

CompileCommandFilter defaultCompilerFilter() {
    return CompileCommandFilter(defaultCompilerFlagFilter, 0);
}

/// Returns: array of default flags to exclude.
auto defaultCompilerFlagFilter() @safe {
    auto app = appender!(FilterClangFlag[])();

    // dfmt off
    foreach (f; [
             // remove basic compile flag irrelevant for AST generation
             "-c", "-o",
             // machine dependent flags
             "-m",
             // machine dependent flags, AVR
             "-nodevicelib", "-Waddr-space-convert",
             // machine dependent flags, VxWorks
             "-non-static", "-Bstatic", "-Bdynamic", "-Xbind-lazy", "-Xbind-now",
             // blacklist all -f because most aren not compatible with clang
             "-f",
             // linker flags, irrelevant for the AST
             "-static", "-shared", "-rdynamic", "-s", "-l", "-L", "-z", "-u", "-T", "-Xlinker",
             // a linker flag with filename as one argument
             "-l",
             // remove some of the preprocessor flags, irrelevant for the AST
             "-MT", "-MF", "-MD", "-MQ", "-MMD", "-MP", "-MG", "-E", "-cc1", "-S", "-M", "-MM", "-###",
             ]) {
        app.put(FilterClangFlag(f));
    }
    // dfmt on

    return app.data;
}

struct CompileCommandFilter {
    FilterClangFlag[] filter;
    int skipCompilerArgs = 0;
}

/// Parsed compiler flags.
struct ParseFlags {
    /// The includes used in the compile command
    static struct Include {
        string payload;
        alias payload this;
    }

    private {
        bool forceSystemIncludes_;
    }

    /// The includes used in the compile command.
    Include[] includes;

    /// System include paths extracted from the compiler used for the file.
    SystemIncludePath[] systemIncludes;

    /// Specific flags for the file as parsed from the DB.
    string[] cflags;

    /// Compiler used to compile the item.
    Compiler compiler;

    void prependCflags(string[] v) {
        this.cflags = v ~ this.cflags;
    }

    void appendCflags(string[] v) {
        this.cflags ~= v;
    }

    /// Set to true to use -I instead of -isystem for system includes.
    auto forceSystemIncludes(bool v) {
        this.forceSystemIncludes_ = v;
        return this;
    }

    bool hasSystemIncludes() @safe pure nothrow const @nogc {
        return systemIncludes.length != 0;
    }

    string toString() @safe pure const {
        import std.format : format;

        return format("Compiler:%s flags: %-(%s %)", compiler, completeFlags);
    }

    /** Easy to use method that has the complete flags ready to use with a GCC
     * complient compiler.
     *
     * This method assumes that -isystem is how to add system flags.
     *
     * Returns: flags with the system flags appended.
     */
    string[] completeFlags() @safe pure nothrow const {
        auto incl_param = forceSystemIncludes_ ? "-I" : "-isystem";

        return cflags.idup ~ systemIncludes.map!(a => [incl_param, a.value]).joiner.array;
    }

    alias completeFlags this;

    this(Include[] incls, string[] flags) {
        this(Compiler.init, incls, SystemIncludePath[].init, flags);
    }

    this(Compiler compiler, Include[] incls, string[] flags) {
        this(compiler, incls, null, flags);
    }

    this(Compiler compiler, Include[] incls, SystemIncludePath[] sysincls, string[] flags) {
        this.compiler = compiler;
        this.includes = incls;
        this.systemIncludes = sysincls;
        this.cflags = flags;
    }
}

/** Filter and normalize the compiler flags.
 *
 *  - Sanitize the compiler command by removing flags matching the filter.
 *  - Remove excess white space.
 *  - Convert all filenames to absolute path.
 */
ParseFlags parseFlag(CompileCommand cmd, const CompileCommandFilter flag_filter) @safe {
    import std.algorithm : among, strip, startsWith, count;
    import std.string : empty, split;

    static bool excludeStartWith(const string raw_flag, const FilterClangFlag[] flag_filter) @safe {
        // the purpuse is to find if any of the flags in flag_filter matches
        // the start of flag.

        bool delegate(const FilterClangFlag) @safe cmp;

        const parts = raw_flag.split('=');
        if (parts.length == 2) {
            // is a -foo=bar flag thus exact match is the only sensible
            cmp = (const FilterClangFlag a) => raw_flag == a.payload;
        } else {
            // the flag has the argument merged thus have to check if the start match
            cmp = (const FilterClangFlag a) => raw_flag.startsWith(a.payload);
        }

        // dfmt off
        return 0 != flag_filter
            .filter!(a => a.kind == FilterClangFlag.Kind.exclude)
            // keep flags that are at least the length of values
            .filter!(a => raw_flag.length >= a.length)
            // if the flag is any of those in filter
            .filter!cmp
            .count();
        // dfmt on
    }

    static bool isQuotationMark(char c) @safe {
        return c == '"';
    }

    static bool isBackslash(char c) @safe {
        return c == '\\';
    }

    static bool isInclude(string flag) @safe {
        return flag.length >= 2 && flag[0 .. 2] == "-I";
    }

    static bool isCombinedIncludeFlag(string flag) @safe {
        // if an include flag make it absolute, as one argument by checking
        // length. 3 is to only match those that are -Ixyz
        return flag.length >= 3 && isInclude(flag);
    }

    static bool isNotAFlag(string flag) @safe {
        // good enough if it seem to be a file
        return flag.length >= 1 && flag[0] != '-';
    }

    /// Flags that take an argument that is a path that need to be transformed
    /// to an absolute path.
    static bool isFlagAndPath(string flag) @safe {
        // list derived from clang --help
        return 0 != flag.among("-I", "-idirafter", "-iframework", "-imacros", "-include-pch",
                "-include", "-iquote", "-isysroot", "-isystem-after", "-isystem", "--sysroot");
    }

    /// Flags that take an argument that is NOT a path.
    static bool isFlagAndValue(string flag) @safe {
        return 0 != flag.among("-D");
    }

    /// Flags that are includes, but contains spaces, are wrapped in quotation marks (or slash).
    static bool isIncludeWithQuotationMark(string flag) @safe {
        // length is checked in isCombinedIncludeFlag
        return isCombinedIncludeFlag(flag) && (isQuotationMark(flag[2]) || isBackslash(flag[2]));
    }

    /// Flags that are paths and contain spaces will start with a quotation mark (or slash).
    static bool isStartingWithQuotationMark(string flag) @safe {
        return !flag.empty && (isQuotationMark(flag[0]) || isBackslash(flag[0]));
    }

    /// When we know we are building a path that is space separated,
    /// the last index of the last string should be a quotation mark.
    static bool isEndingWithQuotationMark(string flag) @safe {
        return !flag.empty && isQuotationMark(flag[$ - 1]);
    }

    static ParseFlags filterPair(string[] r, AbsolutePath workdir,
            const FilterClangFlag[] flag_filter) @safe {
        enum State {
            /// keep the next flag IF none of the other transitions happens
            keep,
            /// forcefully keep the next argument as raw data
            priorityKeepNextArg,
            /// keep the next argument and transform to an absolute path
            pathArgumentToAbsolute,
            /// skip the next arg
            skip,
            /// skip the next arg, if it is not a flag
            skipIfNotFlag,
            /// use the next arg to create a complete path
            checkingForEndQuotation,
        }

        import std.array : Appender, join;
        import std.range : ElementType;

        auto st = State.keep;
        auto rval = appender!(string[]);
        auto includes = appender!(string[]);
        auto compiler = Compiler(r.length == 0 ? null : r[0]);
        auto path = appender!(char[])();

        string removeBackslashesAndQuotes(string arg) {
            import std.conv : text;
            import std.uni : byCodePoint, byGrapheme, Grapheme;

            return arg.byGrapheme.filter!(a => !a.among(Grapheme('\\'),
                    Grapheme('"'))).byCodePoint.text;
        }

        void putNormalizedAbsolute(string arg) {
            import std.path : buildNormalizedPath, absolutePath;

            auto p = buildNormalizedPath(workdir, removeBackslashesAndQuotes(arg)).absolutePath;
            rval.put(p);
            includes.put(p);
        }

        foreach (arg; r) {
            // First states and how to handle those.
            // Then transitions from the state keep, which is the default state.
            //
            // The user controlled excludeStartWith must be before any other
            // conditions after the states. It is to give the user the ability
            // to filter out any flag.

            if (st == State.skip) {
                st = State.keep;
            } else if (st == State.skipIfNotFlag && isNotAFlag(arg)) {
                st = State.keep;
            } else if (st == State.pathArgumentToAbsolute) {
                if (isStartingWithQuotationMark(arg)) {
                    if (isEndingWithQuotationMark(arg)) {
                        st = State.keep;
                        putNormalizedAbsolute(arg);
                    } else {
                        st = State.checkingForEndQuotation;
                        path.put(arg);
                    }
                } else {
                    st = State.keep;
                    putNormalizedAbsolute(arg);
                }
            } else if (st == State.priorityKeepNextArg) {
                st = State.keep;
                rval.put(arg);
            } else if (st == State.checkingForEndQuotation) {
                path.put(" ");
                path.put(arg);
                if (isEndingWithQuotationMark(arg)) {
                    // the end of a divided path
                    st = State.keep;
                    putNormalizedAbsolute(path.data.idup);
                    path.clear;
                }
            } else if (excludeStartWith(arg, flag_filter)) {
                st = State.skipIfNotFlag;
            } else if (isIncludeWithQuotationMark(arg)) {
                rval.put("-I");
                if (arg.length >= 4) {
                    if (isEndingWithQuotationMark(arg)) {
                        // the path is wrapped in quotes (ex ['-I"path/to src"'] or ['-I\"path/to src\"'])
                        putNormalizedAbsolute(arg[2 .. $]);
                    } else {
                        // the path is divided (ex ['-I"path/to', 'src"'] or ['-I\"path/to', 'src\"'])
                        st = State.checkingForEndQuotation;
                        path.put(arg[2 .. $]);
                    }
                }
            } else if (isCombinedIncludeFlag(arg)) {
                rval.put("-I");
                putNormalizedAbsolute(arg[2 .. $]);
            } else if (isFlagAndPath(arg)) {
                rval.put(arg);
                st = State.pathArgumentToAbsolute;
            } else if (isFlagAndValue(arg)) {
                rval.put(arg);
                st = State.priorityKeepNextArg;
            }  // parameter that seem to be filenames, remove
            else if (isNotAFlag(arg)) {
                // skipping
            } else {
                rval.put(arg);
            }
        }
        return ParseFlags(compiler, includes.data.map!(a => ParseFlags.Include(a)).array, rval.data);
    }

    import std.algorithm : min;

    string[] skipArgs = () @safe {
        string[] args;
        if (cmd.command.hasValue)
            args = cmd.command.payload.dup;
        if (args.length > flag_filter.skipCompilerArgs && flag_filter.skipCompilerArgs != 0)
            args = args[min(flag_filter.skipCompilerArgs, args.length) .. $];
        return args;
    }();

    auto pargs = filterPair(skipArgs, cmd.directory, flag_filter.filter);

    return ParseFlags(pargs.compiler, pargs.includes, null, pargs.cflags);
}

/** Convert the string to a CompileCommandDB.
 *
 * Params:
 * path = changes relative paths to be relative this parameter
 * data = input to convert
 */
CompileCommandDB toCompileCommandDB(string data, Path path) @safe {
    auto app = appender!(CompileCommand[])();
    data.parseCommands(CompileDbFile(cast(string) path), app);
    return CompileCommandDB(app.data);
}

CompileCommandDB fromArgCompileDb(AbsolutePath[] paths) @safe {
    return fromArgCompileDb(paths.map!(a => cast(string) a).array);
}

/// Import and merge many compilation databases into one DB.
CompileCommandDB fromArgCompileDb(string[] paths) @safe {
    auto app = appender!(CompileCommand[])();
    paths.orDefaultDb.fromFiles(app);

    return CompileCommandDB(app.data);
}

/// Flags to exclude from the flags passed on to the clang parser.
struct FilterClangFlag {
    string payload;
    alias payload this;

    enum Kind {
        exclude
    }

    Kind kind;
}

@("Should be cflags with all unnecessary flags removed")
unittest {
    auto cmd = toCompileCommand("/home", "file1.cpp", [
            "g++", "-MD", "-lfoo.a", "-l", "bar.a", "-I", "bar", "-Igun", "-c",
            "a_filename.c"
            ], AbsoluteCompileDbDirectory("/home".Path.AbsolutePath), null);
    auto s = cmd.get.parseFlag(defaultCompilerFilter);
    s.cflags.shouldEqual(["-I", "/home/bar", "-I", "/home/gun"]);
    s.includes.shouldEqual(["/home/bar", "/home/gun"]);
}

@("Should be cflags with some excess spacing")
unittest {
    auto cmd = toCompileCommand("/home", "file1.cpp", [
            "g++", "-MD", "-lfoo.a", "-l", "bar.a", "-I", "bar", "-Igun"
            ], AbsoluteCompileDbDirectory("/home".Path.AbsolutePath), null);

    auto s = cmd.get.parseFlag(defaultCompilerFilter);
    s.cflags.shouldEqual(["-I", "/home/bar", "-I", "/home/gun"]);
    s.includes.shouldEqual(["/home/bar", "/home/gun"]);
}

@("Should be cflags with machine dependent removed")
unittest {
    auto cmd = toCompileCommand("/home", "file1.cpp", [
            "g++", "-mfoo", "-m", "bar", "-MD", "-lfoo.a", "-l", "bar.a", "-I",
            "bar", "-Igun", "-c", "a_filename.c"
            ], AbsoluteCompileDbDirectory("/home".Path.AbsolutePath), null);

    auto s = cmd.get.parseFlag(defaultCompilerFilter);
    s.cflags.shouldEqual(["-I", "/home/bar", "-I", "/home/gun"]);
    s.includes.shouldEqual(["/home/bar", "/home/gun"]);
}

@("Should be cflags with all -f removed")
unittest {
    auto cmd = toCompileCommand("/home", "file1.cpp", [
            "g++", "-fmany-fooo", "-I", "bar", "-fno-fooo", "-Igun", "-flolol",
            "-c", "a_filename.c"
            ], AbsoluteCompileDbDirectory("/home".Path.AbsolutePath), null);

    auto s = cmd.get.parseFlag(defaultCompilerFilter);
    s.cflags.shouldEqual(["-I", "/home/bar", "-I", "/home/gun"]);
    s.includes.shouldEqual(["/home/bar", "/home/gun"]);
}

@("shall NOT remove -std=xyz flags")
unittest {
    auto cmd = toCompileCommand("/home", "file1.cpp", [
            "g++", "-std=c++11", "-c", "a_filename.c"
            ], AbsoluteCompileDbDirectory("/home".Path.AbsolutePath), null);

    auto s = cmd.get.parseFlag(defaultCompilerFilter);
    s.cflags.shouldEqual(["-std=c++11"]);
}

@("shall remove -mfloat-gprs=double")
unittest {
    auto cmd = toCompileCommand("/home", "file1.cpp", [
            "g++", "-std=c++11", "-mfloat-gprs=double", "-c", "a_filename.c"
            ], AbsoluteCompileDbDirectory("/home".Path.AbsolutePath), null);
    auto my_filter = CompileCommandFilter(defaultCompilerFlagFilter, 0);
    my_filter.filter ~= FilterClangFlag("-mfloat-gprs=double", FilterClangFlag.Kind.exclude);
    auto s = cmd.get.parseFlag(my_filter);
    s.cflags.shouldEqual(["-std=c++11"]);
}

@("Shall keep all compiler flags as they are")
unittest {
    auto cmd = toCompileCommand("/home", "file1.cpp", ["g++", "-Da", "-D",
            "b"], AbsoluteCompileDbDirectory("/home".Path.AbsolutePath), null);

    auto s = cmd.get.parseFlag(defaultCompilerFilter);
    s.cflags.shouldEqual(["-Da", "-D", "b"]);
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

    enum raw_dummy4 = `[
    {
        "directory": "dir1",
        "arguments": "g++ -Idir1 -c -o binary file3.cpp",
        "file": "file3.cpp",
        "output": "file3.o"
    },
    {
        "directory": "dir2",
        "arguments": "g++ -Idir1 -c -o binary file3.cpp",
        "file": "file3.cpp",
        "output": "file3.o"
    }
]`;

    enum raw_dummy5 = `[
    {
        "directory": "dir1",
        "arguments": ["g++", "-Idir1", "-c", "-o", "binary", "file3.cpp"],
        "file": "file3.cpp",
        "output": "file3.o"
    },
    {
        "directory": "dir2",
        "arguments": ["g++", "-Idir1", "-c", "-o", "binary", "file3.cpp"],
        "file": "file3.cpp",
        "output": "file3.o"
    }
]`;
}

@("Should be a compile command DB")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy1.parseCommands(CompileDbFile(dummy_path), app);
    auto cmds = app.data;

    assert(cmds.length == 1);
    (cast(string) cmds[0].directory).shouldEqual(dummy_dir ~ "/dir1/dir2");
    cmds[0].command.shouldEqual([
            "g++", "-Idir1", "-c", "-o", "binary", "file1.cpp"
            ]);
    (cast(string) cmds[0].file).shouldEqual("file1.cpp");
    (cast(string) cmds[0].absoluteFile).shouldEqual(dummy_dir ~ "/dir1/dir2/file1.cpp");
}

@("Should be a DB with two entries")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy2.parseCommands(CompileDbFile(dummy_path), app);
    auto cmds = app.data;

    (cast(string) cmds[0].file).shouldEqual("file1.cpp");
    (cast(string) cmds[1].file).shouldEqual("file2.cpp");
}

@("Should find filename")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy2.parseCommands(CompileDbFile(dummy_path), app);
    auto cmds = CompileCommandDB(app.data);

    auto found = cmds.find(dummy_dir ~ "/dir/file2.cpp");
    assert(found.length == 1);
    (cast(string) found[0].file).shouldEqual("file2.cpp");
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
    auto app = appender!(CompileCommand[])();
    raw_dummy3.parseCommands(CompileDbFile(dummy_path), app);
    auto cmds = CompileCommandDB(app.data);

    auto found = cmds.find(dummy_dir ~ "/dir2/file3.cpp");
    assert(found.length == 1);

    found.toString.shouldEqual(format("%s/dir2
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

    found.toString.shouldEqual(format("%s/dir
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
    (cast(string) cmds[0].directory).shouldEqual(dummy_dir);
    (cast(string) cmds[0].file).shouldEqual("file1.cpp");
    (cast(string) cmds[0].absoluteFile).shouldEqual(dummy_dir ~ "/file1.cpp");
}

@("Should be a DB read from a relative path with the contained paths adjusted appropriately")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy3.parseCommands(CompileDbFile("path/compilation_db.json"), app);
    auto cmds = CompileCommandDB(app.data);

    // trusted: constructing a path in memory which is never used for writing.
    auto abs_path = () @trusted { return getcwd() ~ "/path"; }();

    auto found = cmds.find(abs_path ~ "/dir2/file3.cpp");
    assert(found.length == 1);

    found.toString.shouldEqual(format("%s/dir2
  file3.cpp
  %s/dir2/file3.cpp
  g++ -Idir1 -c -o binary file3.cpp
", abs_path, abs_path));
}

@("shall extract arguments, file, directory and output with absolute paths")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy4.parseCommands(CompileDbFile("path/compilation_db.json"), app);
    auto cmds = CompileCommandDB(app.data);

    // trusted: constructing a path in memory which is never used for writing.
    auto abs_path = () @trusted { return getcwd() ~ "/path"; }();

    auto found = cmds.find(buildPath(abs_path, "dir2", "file3.cpp"));
    assert(found.length == 1);

    found.toString.shouldEqual(format("%s/dir2
  file3.cpp
  %s/dir2/file3.cpp
  file3.o
  %s/dir2/file3.o
  g++ -Idir1 -c -o binary file3.cpp
", abs_path, abs_path, abs_path));
}

@("shall be the compiler flags derived from the arguments attribute")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy4.parseCommands(CompileDbFile("path/compilation_db.json"), app);
    auto cmds = CompileCommandDB(app.data);

    // trusted: constructing a path in memory which is never used for writing.
    auto abs_path = () @trusted { return getcwd() ~ "/path"; }();

    auto found = cmds.find(buildPath(abs_path, "dir2", "file3.cpp"));
    assert(found.length == 1);

    found[0].parseFlag(defaultCompilerFilter).cflags.shouldEqual([
            "-I", buildPath(abs_path, "dir2", "dir1")
            ]);
}

@("shall find the entry based on an output match")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy4.parseCommands(CompileDbFile("path/compilation_db.json"), app);
    auto cmds = CompileCommandDB(app.data);

    // trusted: constructing a path in memory which is never used for writing.
    auto abs_path = () @trusted { return getcwd() ~ "/path"; }();

    auto found = cmds.find(buildPath(abs_path, "dir2", "file3.o"));
    assert(found.length == 1);

    (cast(string) found[0].absoluteFile).shouldEqual(buildPath(abs_path, "dir2", "file3.cpp"));
}

@("shall parse the compilation database when *arguments* is a json list")
unittest {
    auto app = appender!(CompileCommand[])();
    raw_dummy5.parseCommands(CompileDbFile("path/compilation_db.json"), app);
    auto cmds = CompileCommandDB(app.data);

    // trusted: constructing a path in memory which is never used for writing.
    auto abs_path = () @trusted { return getcwd() ~ "/path"; }();

    auto found = cmds.find(buildPath(abs_path, "dir2", "file3.o"));
    assert(found.length == 1);

    (cast(string) found[0].absoluteFile).shouldEqual(buildPath(abs_path, "dir2", "file3.cpp"));
}

@("shall parse the compilation database and find a match via the glob pattern")
unittest {
    import std.path : baseName;

    auto app = appender!(CompileCommand[])();
    raw_dummy5.parseCommands(CompileDbFile("path/compilation_db.json"), app);
    auto cmds = CompileCommandDB(app.data);

    auto found = cmds.find("*/dir2/file3.cpp");
    assert(found.length == 1);

    found[0].absoluteFile.baseName.shouldEqual("file3.cpp");
}

@("shall extract filepath from includes correctly when there is spaces in the path")
unittest {
    auto cmd = toCompileCommand("/home", "file.cpp", [
            "-I", `"dir with spaces"`, "-I", `\"dir with spaces\"`
            ], AbsoluteCompileDbDirectory("/home".Path.AbsolutePath), null);
    auto pargs = cmd.get.parseFlag(defaultCompilerFilter);
    pargs.cflags.shouldEqual([
            "-I", "/home/dir with spaces", "-I", "/home/dir with spaces"
            ]);
    pargs.includes.shouldEqual([
            "/home/dir with spaces", "/home/dir with spaces"
            ]);
}

@("shall handle path with spaces, both as separate string and combined with backslash")
unittest {
    auto cmd = toCompileCommand("/project", "file.cpp", [
            "-I", `"separate dir/with space"`, "-I", `\"separate dir/with space\"`,
            `-I"combined dir/with space"`, `-I\"combined dir/with space\"`,
            ], AbsoluteCompileDbDirectory("/project".Path.AbsolutePath), null);
    auto pargs = cmd.get.parseFlag(defaultCompilerFilter);
    pargs.cflags.shouldEqual([
            "-I", "/project/separate dir/with space", "-I",
            "/project/separate dir/with space", "-I",
            "/project/combined dir/with space", "-I",
            "/project/combined dir/with space"
            ]);
    pargs.includes.shouldEqual([
            "/project/separate dir/with space", "/project/separate dir/with space",
            "/project/combined dir/with space", "/project/combined dir/with space"
            ]);
}

@("shall handle path with consecutive spaces")
unittest {
    auto cmd = toCompileCommand("/project", "file.cpp",
            [
                `-I"one space/lots of     space"`,
                `-I\"one space/lots of     space\"`, `-I`,
                `"one space/lots of     space"`, `-I`,
                `\"one space/lots of     space\"`,
            ], AbsoluteCompileDbDirectory("/project".Path.AbsolutePath), null);
    auto pargs = cmd.get.parseFlag(defaultCompilerFilter);
    pargs.cflags.shouldEqual([
            "-I", "/project/one space/lots of     space", "-I",
            "/project/one space/lots of     space", "-I",
            "/project/one space/lots of     space", "-I",
            "/project/one space/lots of     space",
            ]);
    pargs.includes.shouldEqual([
            "/project/one space/lots of     space",
            "/project/one space/lots of     space",
            "/project/one space/lots of     space",
            "/project/one space/lots of     space"
            ]);
}
