/**
Copyright: Copyright (c) 2016-2019, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.utility.virtualfilesystem;

import clang.c.Index : CXUnsavedFile;

public import dextool.type : Path;
public import blob_model : BlobVfs;

/** Convert to an array that can be passed on to clang to use as in-memory source code.
 *
 * Trusted: operates on files handled by a VirtualFileSystem that ensues that
 * they exists. The VFS has taken care of validating the files.
 */
CXUnsavedFile[] toClangFiles(ref BlobVfs vfs) @trusted {
    import std.algorithm : map;
    import std.array : array;
    import std.string : toStringz;

    return vfs.uris.map!((a) {
        auto s = vfs.get(a).content[];
        auto fname = (cast(string) a).toStringz;
        return CXUnsavedFile(fname, cast(char*) s.ptr, s.length);
    }).array();
}
