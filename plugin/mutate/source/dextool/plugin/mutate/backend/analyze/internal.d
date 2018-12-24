/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.analyze.internal;

import dextool.plugin.mutate.backend.utility : Checksum, checksum, tokenize;
import dextool.type : Path;

public import dextool.plugin.mutate.backend.type : Token;

@safe:

/// Presents an interface that returns the tokens in the file.
interface TokenStream {
    Token[] getTokens(Path p);
}

/// Cache computation expensive operations that are reusable between analyze of
/// individual files.
class Cache {
    import cachetools : CacheLRU;

    private {
        CacheLRU!(Path, Checksum) file_;
        CacheLRU!(Path, Checksum) path_;
        CacheLRU!(Path, Token[]) fileToken_;
    }

    this() {
        this.file_ = new typeof(file_);
        this.path_ = new typeof(path_);

        this.fileToken_ = new typeof(fileToken_);
        // guessing that 30s and keeping the last 64 is "good enough".
        // TODO: gather metrics or make it configurable.
        this.fileToken_.size = 64;
        this.fileToken_.ttl = 30;
    }

    /** Calculate the checksum for the file content.
     */
    Checksum getFileChecksum(Path p, const(ubyte)[] data) {
        typeof(return) rval;
        auto query = file_.get(p);
        if (query.isNull) {
            rval = checksum(data);
            file_.put(p, rval);
        } else {
            rval = query.get;
        }
        return rval;
    }

    /** Calculate the checksum of the file path.
     */
    Checksum getPathChecksum(Path p) {
        typeof(return) rval;
        auto query = path_.get(p);
        if (query.isNull) {
            rval = checksum(cast(const(ubyte)[]) p);
            path_.put(p, rval);
        } else {
            rval = query.get;
        }
        return rval;
    }

    /** Returns: the files content converted to tokens.
     */
    Token[] getTokens(Path p, TokenStream tstream) {
        typeof(return) rval;
        auto query = fileToken_.get(p);
        if (query.isNull) {
            rval = tstream.getTokens(p);
            fileToken_.put(p, rval);
        } else {
            rval = query.get;
        }
        return rval;
    }
}
