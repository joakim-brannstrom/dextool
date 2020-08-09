/**
Date: 2015-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool.type;

static import my.path;

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

alias Path = my.path.Path;
alias AbsolutePath = my.path.AbsolutePath;

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

@("shall be an instantiation of Exists")
nothrow unittest {
    // the file is not expected to exist.

    try {
        auto p = makeExists(AbsolutePath(Path("foo")));
    } catch (Exception e) {
    }
}
