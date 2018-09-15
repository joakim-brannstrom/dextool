/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.utility.virtualfilesystem;

import clang.c.Index : CXUnsavedFile;

public import dextool.type : FileName;
public import dextool.vfs : VirtualFileSystem;

/** Convert to an array that can be passed on to clang to use as in-memory source code.
 *
 * Trusted: operates on files handled by a VirtualFileSystem that ensues that
 * they exists. The VFS has taken care of validating the files.
 */
CXUnsavedFile[] toClangFiles(ref VirtualFileSystem vfs) @trusted {
    import std.algorithm : map;
    import std.array : array;
    import std.string : toStringz;

    return vfs.files.map!((a) {
        auto s = vfs.open(a)[];
        auto strz = (cast(char[]) a).toStringz;
        return CXUnsavedFile(strz, cast(char*) s.ptr, s.length);
    }).array();
}
