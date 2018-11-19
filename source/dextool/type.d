/**
Date: 2015-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool.type;

public import dextool.compilation_db : FilterClangFlag;

@safe:

enum ExitStatusType {
    Ok,
    Errors
}

/** Prefix used for prepending generated code with a unique string to avoid
 * name collisions.
 * See specific functions for how it is used.
 */
struct StubPrefix {
    string payload;
    alias payload this;
}

/// Prefix used for prepending generated files.
struct FilePrefix {
    string payload;
    alias payload this;
}

struct MainFileName {
    string payload;
    alias payload this;
}

struct MainName {
    string payload;
    alias payload this;
}

struct MainNs {
    string payload;
    alias payload this;
}

struct MainInterface {
    string payload;
    alias payload this;
}

struct DextoolVersion {
    string payload;
    alias payload this;
}

struct CustomHeader {
    string payload;
    alias payload this;
}

/// The raw arguments from the command line.
struct RawCliArguments {
    string[] payload;
    alias payload this;
}

/// Used when writing data to files on the filesystem.
enum WriteStrategy {
    overwrite,
    skip
}

//TODO remove FileNames
struct FileNames {
    string[] payload;
    alias payload this;
}

struct InFiles {
    string[] payload;
    alias payload this;
}

/// No guarantee regarding the path. May be absolute, relative, contain a '~'.
/// The user of this type must do all the safety checks to ensure that the
/// datacontained in valid.
struct Path {
    string payload;
    alias payload this;
}

/// ditto
struct DirName {
    Path payload;
    alias payload this;

    pure nothrow @nogc this(string p) {
        payload = Path(p);
    }
}

/// ditto
struct FileName {
pure @nogc nothrow:

    Path payload;
    alias payload this;

    this(Path p) {
        payload = p;
    }

    pure nothrow @nogc this(string p) {
        payload = Path(p);
    }
}

/** The path is guaranteed to be the absolute path.
 *
 * The user of the type has to make an explicit judgment when using the
 * assignment operator. Either a `FileName` and then pay the cost of the path
 * expansion or an absolute which is already assured to be _ok_.
 * This divides the domain in two, one unchecked and one checked.
 */
struct AbsolutePath {
    import std.path : expandTilde, buildNormalizedPath;

    Path payload;
    alias payload this;

    invariant {
        import std.path : isAbsolute;

        assert(payload.length == 0 || payload.isAbsolute);
    }

    immutable this(AbsolutePath p) {
        this.payload = p.payload;
    }

    this(Path p) {
        auto p_expand = () @trusted { return p.expandTilde; }();
        // the second buildNormalizedPath is needed to correctly resolve "."
        // otherwise it is resolved to /foo/bar/.
        payload = buildNormalizedPath(p_expand).asAbsNormPath.Path;
    }

    /// Build the normalised path from workdir.
    this(Path p, DirName workdir) {
        auto p_expand = () @trusted { return p.expandTilde; }();
        auto workdir_expand = () @trusted { return workdir.expandTilde; }();
        // the second buildNormalizedPath is needed to correctly resolve "."
        // otherwise it is resolved to /foo/bar/.
        payload = buildNormalizedPath(workdir_expand, p_expand).asAbsNormPath.Path;
    }

    void opAssign(FileName p) {
        payload = typeof(this)(p).payload;
    }

    pure nothrow @nogc void opAssign(AbsolutePath p) {
        payload = p.payload;
    }

    pure nothrow const @nogc FileName opCast(T : FileName)() {
        return FileName(payload);
    }

    pure nothrow const @nogc string opCast(T : string)() {
        return payload;
    }
}

struct AbsoluteFileName {
    AbsolutePath payload;
    alias payload this;

    pure nothrow @nogc this(AbsolutePath p) {
        payload = p;
    }
}

struct AbsoluteDirectory {
    AbsolutePath payload;
    alias payload this;

    pure nothrow @nogc this(AbsolutePath p) {
        payload = p;
    }
}

/** During construction checks that the file exists on the filesystem.
 *
 * If it doesn't exist it will throw an Exception.
 */
struct Exists(T) {
    AbsolutePath payload;
    alias payload this;

    this(AbsolutePath p) {
        import std.file : exists, FileException;

        if (!exists(p)) {
            throw new FileException("File do not exist: " ~ cast(string) p);
        }

        payload = p;
    }

    this(Exists!T p) {
        payload = p.payload;
    }

    void opAssign(Exists!T p) pure nothrow @nogc {
        payload = p;
    }
}

auto makeExists(T)(T p) {
    return Exists!T(p);
}

@("shall always be the absolute path")
unittest {
    import std.algorithm : canFind;
    import std.path;
    import unit_threaded;

    AbsolutePath(FileName("~/foo")).canFind('~').shouldEqual(false);
    AbsolutePath(FileName("foo")).isAbsolute.shouldEqual(true);
}

@("shall expand . without any trailing /.")
unittest {
    import std.algorithm : canFind;
    import unit_threaded;

    AbsolutePath(FileName(".")).canFind('.').shouldBeFalse;
    AbsolutePath(FileName("."), DirName(".")).canFind('.').shouldBeFalse;
}

@("shall be an instantiation of Exists")
nothrow unittest {
    // the file is not expected to exist.

    try {
        auto p = makeExists(AbsolutePath(FileName("foo")));
    } catch (Exception e) {
    }
}

private:

string asAbsNormPath(string path) @trusted {
    import std.path;
    import std.conv : to;

    return to!string(path.asAbsolutePath.asNormalizedPath);
}
