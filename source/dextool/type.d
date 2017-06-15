/**
Date: 2015-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool.type;

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

/// Flags to exclude from the flags passed on to the clang parser.
struct FilterClangFlag {
    string payload;
    alias payload this;

    enum Kind {
        exclude
    }

    Kind kind;
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
    Path payload;
    alias payload this;

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
    import std.path : expandTilde, buildNormalizedPath, absolutePath;

    Path payload;
    alias payload this;

    invariant {
        import std.algorithm : canFind;
        import std.path : isAbsolute;

        assert(payload.length == 0 || payload.isAbsolute);
        // A path is absolute if it starts with a /.
        // But a ~ can be injected in the built, absolute path, when two or
        // more paths are combined with buildNormalizedPath and one of the
        // paths (not the first one) contains a ~.
        // This is functionally wrong, and even an invalid path.
        assert(!payload.payload.canFind('~'));
    }

    this(FileName p) {
        auto p_expand = () @trusted{ return p.expandTilde; }();
        payload = buildNormalizedPath(p_expand).absolutePath.Path;
    }

    /// Build the normalised path from workdir.
    this(FileName p, DirName workdir) {
        auto p_expand = () @trusted{ return p.expandTilde; }();
        auto workdir_expand = () @trusted{ return workdir.expandTilde; }();
        payload = buildNormalizedPath(workdir_expand, p_expand).absolutePath.Path;
    }

    void opAssign(FileName p) {
        payload = typeof(this)(p).payload;
    }

    pure nothrow @nogc void opAssign(AbsolutePath p) {
        payload = p.payload;
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

@("shall always be the absolute path")
unittest {
    import std.algorithm : canFind;
    import std.path;
    import unit_threaded;

    AbsolutePath(FileName("~/foo")).canFind('~').shouldEqual(false);
    AbsolutePath(FileName("foo")).isAbsolute.shouldEqual(true);
}
