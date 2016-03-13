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

struct Compiler {
    import std.algorithm : any, map;
    import std.path : buildPath;
    import std.meta : staticMap;

    private {
        version (Windows)
            enum root = `C:\`;

        else
            enum root = "/";

        string virtualPath_;

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

    CXUnsavedFile[] extraHeaders() {
        import std.array : array;
        import std.string : toStringz;

        return internalHeaders.map!((e) {
            auto path = buildPath(virtualPath, e.filename);
            return CXUnsavedFile(path.toStringz, e.content.ptr, e.content.length);
        }).array();
    }

private:

    string virtualPath() {
        import std.conv : text;
        import std.random;

        if (virtualPath_.any)
            return virtualPath_;

        return virtualPath_ = buildPath(root, text(uniform(1, 10_000_000)));
    }
}
