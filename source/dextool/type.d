/**
Date: 2015-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool.type;

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

struct DirName {
    string payload;
    alias payload this;
}

/// No guarantee that it is absolute etc. Up to the user to ensure of the type
/// to do the checking.
struct FileName {
    string payload;
    alias payload this;
}

/** The path is guaranteed to be the absolute path.
 *
 * The user of the type has to make an explicit judgement when using the
 * assignment operator. Either a `FileName` and then pay the cost of the path
 * expansion or an absolute which is already assured to be _ok_.
 * This divives the domain in two, one uncheck and one check.
 *
 * Tilde is not allowed to be part of the payload.
 */
@safe struct AbsolutePath {
    import std.path : expandTilde, buildNormalizedPath, asAbsolutePath,
        absolutePath;

    invariant {
        import std.algorithm : canFind;
        import std.path : isAbsolute;

        assert(payload.length == 0 || payload.isAbsolute);
        assert(!payload.canFind('~'));
    }

    this(FileName p) {
        auto p_expand = () @trusted{ return p.expandTilde; }();
        payload = buildNormalizedPath(p_expand).absolutePath;
    }

    /// Build the normalised path from workdir.
    this(FileName p, DirName workdir) {
        auto p_expand = () @trusted{ return p.expandTilde; }();
        auto workdir_expand = () @trusted{ return workdir.expandTilde; }();
        payload = buildNormalizedPath(workdir_expand, p_expand).absolutePath;
    }

    /// Build the normalised path from workdir.
    this(AbsolutePath p, AbsolutePath workdir) {
        payload = buildNormalizedPath(workdir, p);
    }

    void opAssign(FileName p) {
        payload = typeof(this)(p).payload;
    }

    void opAssign(AbsolutePath p) {
        payload = p.payload;
    }

    string payload;
    alias payload this;
}

@("shall always be the absolute path")
unittest {
    import std.algorithm : canFind;
    import std.path;
    import unit_threaded;

    AbsolutePath(FileName("~/foo")).canFind('~').shouldEqual(false);
    AbsolutePath(FileName("foo")).isAbsolute.shouldEqual(true);
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
