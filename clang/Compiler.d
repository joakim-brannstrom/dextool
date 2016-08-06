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

struct Compiler {
    import std.algorithm : any, map;
    import std.path : buildPath;
    import std.meta : staticMap;

    private {
        version (Windows) {
            enum root = `C:\`;
        } else {
            enum root = "/";
        }
        enum root_suffix = "dextool_clang";

        string virtual_path;

        static template toInternalHeader(string file) {
            enum toInternalHeader = InternalHeader(file, import(file));
        }

        static struct InternalHeader {
            string filename;
            string content;
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

    string[] extraIncludePaths() {
        return [virtualPath];
    }

    void addInMemorySource(string filename, string content) {
        extraFiles_ ~= InternalHeader(filename, content);
    }

    CXUnsavedFile[] extraFiles() {
        import std.array : array;
        import std.string : toStringz;

        return extraFiles_.map!((e) {
            return CXUnsavedFile(e.filename.toStringz, e.content.ptr, e.content.length);
        }).array();
    }

    CXUnsavedFile[] extraHeaders() {
        import std.array : array;
        import std.string : toStringz;

        return internalHeaders.map!((e) {
            auto path = buildPath(virtualPath, e.filename);
            return CXUnsavedFile(path.toStringz, e.content.ptr, e.content.length);
        }).array();
    }

private:

    InternalHeader[] extraFiles_;

    string virtualPath() {
        if (virtual_path.any)
            return virtual_path;

        return virtual_path = buildPath(root, uniquePathId, root_suffix);
    }
}
