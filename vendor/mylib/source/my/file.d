/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module my.file;

import std.algorithm : canFind;
import std.file : mkdirRecurse, exists, copy, dirEntries, SpanMode;
import std.path : relativePath, buildPath, dirName;

public import std.file : attrIsDir, attrIsFile, attrIsSymlink, isFile, isDir, isSymlink;

import my.path;

/** A `nothrow` version of `getAttributes` in Phobos.
 *
 * man 7 inode search for S_IFMT
 * S_ISUID     04000   set-user-ID bit
 * S_ISGID     02000   set-group-ID bit (see below)
 * S_ISVTX     01000   sticky bit (see below)
 *
 * S_IRWXU     00700   owner has read, write, and execute permission
 * S_IRUSR     00400   owner has read permission
 * S_IWUSR     00200   owner has write permission
 * S_IXUSR     00100   owner has execute permission
 *
 * S_IRWXG     00070   group has read, write, and execute permission
 * S_IRGRP     00040   group has read permission
 * S_IWGRP     00020   group has write permission
 * S_IXGRP     00010   group has execute permission
 *
 * S_IRWXO     00007   others (not in group) have read, write, and execute permission
 * S_IROTH     00004   others have read permission
 * S_IWOTH     00002   others have write permission
 * S_IXOTH     00001   others have execute permission
 *
 * The idea of doing it like this is from WebFreaks001 pull request
 * [DCD pullrequest](https://github.com/dlang-community/dsymbol/pull/151/files).
 *
 * Returns: true on success and thus `attributes` contains a valid value.
 */
bool getAttrs(const Path file, ref uint attributes) @safe nothrow {
    import core.sys.posix.sys.stat : stat, stat_t;
    import my.cstring;

    static bool trustedAttrs(const Path file, ref stat_t st) @trusted {
        return stat(file.toString.tempCString, &st) == 0;
    }

    stat_t st;
    bool status = trustedAttrs(file, st);
    attributes = st.st_mode;
    return status;
}

/** A `nothrow` version of `getLinkAttributes` in Phobos.
 *
 * Returns: true on success and thus `attributes` contains a valid value.
 */
bool getLinkAttrs(const Path file, ref uint attributes) @safe nothrow {
    import core.sys.posix.sys.stat : lstat, stat_t;
    import my.cstring;

    static bool trustedAttrs(const Path file, ref stat_t st) @trusted {
        return lstat(file.toString.tempCString, &st) == 0;
    }

    stat_t st;
    bool status = trustedAttrs(file, st);
    attributes = st.st_mode;
    return status;
}

/** A `nothrow` version of `setAttributes` in Phobos.
 */
bool setAttrs(const Path file, const uint attributes) @trusted nothrow {
    import core.sys.posix.sys.stat : chmod;
    import my.cstring;

    return chmod(file.toString.tempCString, attributes) == 0;
}

/// Returns: true if `file` exists.
bool exists(const Path file) @safe nothrow {
    uint attrs;
    return getAttrs(file, attrs);
}

/** Returns: true if `file` exists and is a file.
 *
 * Source: [DCD](https://github.com/dlang-community/dsymbol/blob/master/src/dsymbol/modulecache.d)
 */
bool existsAnd(alias pred : isFile)(const Path file) @safe nothrow {
    uint attrs;
    if (!getAttrs(file, attrs))
        return false;
    return attrIsFile(attrs);
}

/** Returns: true if `file` exists and is a directory.
 *
 * Source: [DCD](https://github.com/dlang-community/dsymbol/blob/master/src/dsymbol/modulecache.d)
 */
bool existsAnd(alias pred : isDir)(const Path file) @safe nothrow {
    uint attrs;
    if (!getAttrs(file, attrs))
        return false;
    return attrIsDir(attrs);
}

/** Returns: true if `file` exists and is a symlink.
 *
 * Source: [DCD](https://github.com/dlang-community/dsymbol/blob/master/src/dsymbol/modulecache.d)
 */
bool existsAnd(alias pred : isSymlink)(const Path file) @safe nothrow {
    uint attrs;
    if (!getLinkAttrs(file, attrs))
        return false;
    return attrIsSymlink(attrs);
}

/// Example:
unittest {
    import std.file : remove, symlink, mkdir;
    import std.format : format;
    import std.stdio : File;

    const base = Path(format!"%s_%s"(__FILE__, __LINE__)).baseName;
    const Path fname = base ~ "_file";
    const Path dname = base ~ "_dir";
    const Path symname = base ~ "_symlink";
    scope (exit)
        () {
        foreach (f; [fname, dname, symname]) {
            if (exists(f))
                remove(f);
        }
    }();

    File(fname, "w").write("foo");
    mkdir(dname);
    symlink(fname, symname);

    assert(exists(fname));
    assert(existsAnd!isFile(fname));
    assert(existsAnd!isDir(dname));
    assert(existsAnd!isSymlink(symname));
}

/// Copy `src` into `dst` recursively.
void copyRecurse(Path src, Path dst) {
    foreach (a; dirEntries(src.toString, SpanMode.depth)) {
        const s = relativePath(a.name, src.toString);
        const d = buildPath(dst.toString, s);
        if (!exists(d.dirName)) {
            mkdirRecurse(d.dirName);
        }
        if (!existsAnd!isDir(Path(a))) {
            copy(a.name, d);
        }
    }
}

/// Make a file executable by all users on the system.
void setExecutable(Path p) nothrow {
    import core.sys.posix.sys.stat;
    import std.file : getAttributes, setAttributes;

    uint attrs;
    if (getAttrs(p, attrs)) {
        setAttrs(p, attrs | S_IXUSR | S_IXGRP | S_IXOTH);
    }
}

/// Check if a file is executable.
bool isExecutable(Path p) nothrow {
    import core.sys.posix.sys.stat;
    import std.file : getAttributes;

    uint attrs;
    if (getAttrs(p, attrs)) {
        return (attrs & (S_IXUSR | S_IXGRP | S_IXOTH)) != 0;
    }
    return false;
}

/** As the unix command `which` it searches in `dirs` for an executable `name`.
 *
 * The difference in the behavior is that this function returns all
 * matches and supports globbing (use of `*`).
 *
 * Example:
 * ---
 * writeln(which([Path("/bin")], "ls"));
 * writeln(which([Path("/bin")], "l*"));
 * ---
 */
AbsolutePath[] which(Path[] dirs, string name) {
    import std.algorithm : map, filter, joiner, copy;
    import std.array : appender;
    import std.file : dirEntries, SpanMode;
    import std.path : baseName, globMatch;

    auto res = appender!(AbsolutePath[])();
    dirs.filter!(a => exists(a))
        .map!(a => dirEntries(a, SpanMode.shallow))
        .joiner
        .map!(a => Path(a))
        .filter!(a => isExecutable(a))
        .filter!(a => globMatch(a.baseName, name))
        .map!(a => AbsolutePath(a))
        .copy(res);
    return res.data;
}

@("shall return all locations of ls")
unittest {
    assert(which([Path("/bin")], "mv") == [AbsolutePath("/bin/mv")]);
    assert(which([Path("/bin")], "l*").length >= 1);
}

AbsolutePath[] whichFromEnv(string envKey, string name) {
    import std.algorithm : splitter, map, filter;
    import std.process : environment;
    import std.array : empty, array;

    auto dirs = environment.get(envKey, null).splitter(":").filter!(a => !a.empty)
        .map!(a => Path(a))
        .array;
    return which(dirs, name);
}

@("shall return all locations of ls by using the environment variable PATH")
unittest {
    assert(canFind(whichFromEnv("PATH", "mv"), AbsolutePath("/bin/mv")));
}
