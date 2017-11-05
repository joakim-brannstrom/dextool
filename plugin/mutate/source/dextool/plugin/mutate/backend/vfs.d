/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file contains functionality to manipulate the VirtualFileSystem.
*/
module dextool.plugin.mutate.backend.vfs;

import cpptooling.utility.virtualfilesystem : VirtualFileSystem;
import cpptooling.utility.virtualfilesystem : vfsFileName = FileName;
import dextool.type : AbsolutePath;

/// Offset range. It is a [) kind.
struct Offset {
    uint start;
    uint end;
}

auto drop(T = string)(ref VirtualFileSystem vfs, const AbsolutePath fname, const Offset offset) {
    import cpptooling.utility.virtualfilesystem;

    auto content = vfs.slice!T(cast(vfsFileName) cast(string) fname);

    return DropRange!T(content[0 .. offset.start], content[offset.end .. $]);
}

private:

struct DropRange(T) {
    private {
        T[2] data;
        size_t idx;
    }

    this(T d0, T d1) {
        data = [d0, d1];
    }

    T front() @safe pure nothrow {
        assert(!empty, "Can't get front of an empty range");
        return data[idx];
    }

    void popFront() @safe pure nothrow {
        assert(!empty, "Can't pop front of an empty range");
        ++idx;
    }

    bool empty() @safe pure nothrow const @nogc {
        return idx == data.length;
    }
}
