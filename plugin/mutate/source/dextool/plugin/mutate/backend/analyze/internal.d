/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.analyze.internal;

import dextool.plugin.mutate.backend.utility : Checksum, checksum;
import dextool.type : Path;

@safe:

/// Cache computation expensive operations that are reusable between analyze of
/// individual files.
class Cache {
    import cachetools : CacheLRU;

    private {
        CacheLRU!(Path, Checksum) file_;
        CacheLRU!(Path, Checksum) fileToken_;
    }

    this() {
        this.file_ = new typeof(file_);
        this.fileToken_ = new typeof(fileToken_);
    }

    void putFile(Path p, Checksum cs) {
        file_.put(p, cs);
    }

    void putFileToken(Path p, Checksum cs) {
        fileToken_.put(p, cs);
    }

    private static string mixinQuery(string cache) {
        import std.format : format;

        return format(q{
            Checksum cs;
            auto query = %s.get(p);
            if (query.isNull) {
                cs = checksum(data);
                %s.put(p, cs);
            } else {
                cs = query.get;
            }
        return cs;
        }, cache, cache);
    }

    /** Calculate the checksum for the file content.
     */
    Checksum getFileChecksum(Path p, const(ubyte)[] data) {
        mixin(mixinQuery("file_"));
    }

    /** Calculate the checksum for the file content.
     *
     * TODO: The pah should be a checksum based on the compiler flags and path
     * the compiler flags may affect the tokens.
     */
    Checksum getFileTokenChecksum(Path p, const(ubyte)[] data) {
        mixin(mixinQuery("fileToken_"));
    }
}
