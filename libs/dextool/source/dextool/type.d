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

struct DextoolVersion {
    string payload;
    alias payload this;
}

/// No guarantee regarding the path. May be absolute, relative, contain a '~'.
/// The user of this type must do all the safety checks to ensure that the
/// datacontained in valid.
struct Path {
    string payload;
    alias payload this;

    this(string s) @safe nothrow {
        const h = s.hashOf;
        if (auto v = h in pathCache) {
            payload = *v;
        } else {
            pathCache[h] = s;
            payload = s;
        }
    }

    bool empty() @safe pure nothrow const @nogc {
        return payload.length == 0;
    }

    bool opEquals(const string s) @safe pure nothrow const @nogc {
        return payload == s;
    }

    bool opEquals(const AbsolutePath s) @safe pure nothrow const @nogc {
        return payload == s.payload;
    }

    size_t toHash() @safe pure nothrow const @nogc scope {
        return payload.hashOf;
    }

    private static string fromCache(size_t h) {
        if (pathCache.length > 1024) {
            pathCache = null;
        }
        if (auto v = h in pathCache) {
            return *v;
        }
        return null;
    }
}

private {
    // Reduce memory usage by reusing paths.
    private string[size_t] pathCache;
}

/** The path is guaranteed to be the absolute path.
 *
 * The user of the type has to make an explicit judgment when using the
 * assignment operator. Either a `Path` and then pay the cost of the path
 * expansion or an absolute which is already assured to be _ok_.
 * This divides the domain in two, one unchecked and one checked.
 */
struct AbsolutePath {
    import std.path : buildNormalizedPath, asAbsolutePath, asNormalizedPath;
    import std.utf : toUTF8;

    Path payload;
    alias payload this;

    invariant {
        import std.path : isAbsolute;

        assert(payload.empty || payload.isAbsolute);
    }

    this(Path p) {
        // the second buildNormalizedPath is needed to correctly resolve "."
        // otherwise it is resolved to /foo/bar/.
        payload = buildNormalizedPath(expand(p)).asAbsolutePath.asNormalizedPath.toUTF8.Path;
    }

    /// Build the normalised path from workdir.
    this(Path p, Path workdir) {
        // the second buildNormalizedPath is needed to correctly resolve "."
        // otherwise it is resolved to /foo/bar/.
        payload = buildNormalizedPath(expand(workdir), expand(p))
            .asAbsolutePath.asNormalizedPath.toUTF8.Path;
    }

    pure nothrow @nogc void opAssign(AbsolutePath p) {
        payload = p.payload;
    }

    pure nothrow const @nogc string opCast(T : string)() {
        return payload;
    }

    bool opEquals(const string s) @safe pure nothrow const @nogc {
        return payload == s;
    }

    bool opEquals(const Path s) @safe pure nothrow const @nogc {
        return payload == s.payload;
    }

    bool opEquals(const AbsolutePath s) @safe pure nothrow const @nogc {
        return payload == s.payload;
    }

    private static Path expand(Path p) @trusted {
        import std.path : expandTilde;

        return p.expandTilde.Path;
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

    AbsolutePath(Path("~/foo")).canFind('~').shouldEqual(false);
    AbsolutePath(Path("foo")).isAbsolute.shouldEqual(true);
}

@("shall expand . without any trailing /.")
unittest {
    import std.algorithm : canFind;
    import unit_threaded;

    AbsolutePath(Path(".")).canFind('.').shouldBeFalse;
    AbsolutePath(Path("."), Path(".")).canFind('.').shouldBeFalse;
}

@("shall be an instantiation of Exists")
nothrow unittest {
    // the file is not expected to exist.

    try {
        auto p = makeExists(AbsolutePath(Path("foo")));
    } catch (Exception e) {
    }
}
