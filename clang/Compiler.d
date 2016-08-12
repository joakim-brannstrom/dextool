/**
 * Copyright: Copyright (c) 2015 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg
 * Version: 1.1
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 *
 * History:
 *  1.0 Initial created: Jan 31, 2015 $(BR)
 *      Jacob Carlborg
 *  1.1 updated to clang 3.6 with additional internal header $(BR)
 *      Joakim Brännström
 */
module clang.Compiler;

import deimos.clang.index;

private string uniquePathId;

static this() {
    import std.conv : text;
    import std.random;

    // Keep the identifier the same while running.
    // Easier for the user to reason about what it is, where it comes from.
    uniquePathId = text(uniform(1, 10_000_000));
}

struct InternalHeader {
    string filename;
    string content;
}

/** Clang specific in-memory files.
 *
 * Imported into the binary during compilation time.
 */
struct Compiler {
    import std.algorithm : any, map;
    import std.path : buildPath;
    import std.meta : staticMap;

    InternalHeader[] extraHeaders() {
        import std.array : array;
        import std.string : toStringz;

        return internalHeaders.map!((e) {
            auto path = buildPath(virtualPath, e.filename);
            return InternalHeader(path, e.content);
        }).array();
    }

private:
    version (Windows) {
        enum root = `C:\`;
    } else {
        enum root = "/";
    }
    enum root_suffix = "dextool_clang";

    static template toInternalHeader(string file) {
        enum toInternalHeader = InternalHeader(file, import(file));
    }

    // dfmt off
    enum internalHeaders = [
        staticMap!(toInternalHeader,
                   "float.h",
                   "limits.h",
                   "stdalign.h",
                   "stdarg.h",
                   "stdbool.h",
                   "stddef.h",
                   "stdint.h",
                   "__stddef_max_align_t.h")
    ];
    // dfmt on
}

private:

string virtualPath() {
    return buildPath(root, uniquePathId, root_suffix);
}

struct HeaderResult {
    private size_t idx;

    InternalHeader front() @safe pure nothrow {
        assert(!empty, "Can't get front of an empty range");
        return  /+4: return the element+/ ;
    }

    void popFront() @safe pure nothrow {
        assert(!empty, "Can't pop front of an empty range");
        /+6: remove the front element of the range+/
    }

    bool empty() @safe pure nothrow const @nogc {
        return  /+9: true if empty, false otherwise+/ ;
    }
}
