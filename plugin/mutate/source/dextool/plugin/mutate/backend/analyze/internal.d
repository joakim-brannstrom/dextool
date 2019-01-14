/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.analyze.internal;

import logger = std.experimental.logger;

import dextool.plugin.mutate.backend.utility : Checksum, checksum, tokenize;
import dextool.type : Path, AbsolutePath;

public import dextool.plugin.mutate.backend.type : Token;

@safe:

/// Presents an interface that returns the tokens in the file.
interface TokenStream {
    /// All tokens.
    Token[] getTokens(Path p);

    /// All tokens except comments.
    Token[] getFilteredTokens(Path p);
}

/** Cache computation expensive operations that are reusable between analyze of
 * individual files.
 *
 * Do **NOT** use anything else than builtin types and strings as keys.
 * Such as a struct with an alias this string.
 */
class Cache {
    import cachetools : CacheLRU;

    private {
        CacheLRU!(string, Checksum) file_;
        CacheLRU!(string, Checksum) path_;
        CacheLRU!(string, Token[]) fileToken_;
        CacheLRU!(string, Token[]) fileFilteredToken_;
        bool enableLog_;
    }

    this() {
        this.file_ = new typeof(file_);
        this.path_ = new typeof(path_);

        this.fileToken_ = new typeof(fileToken_);
        // guessing that 30s and keeping the last 64 is "good enough".
        // TODO: gather metrics or make it configurable.
        this.fileToken_.size = 64;
        this.fileToken_.ttl = 30;

        this.fileFilteredToken_ = new typeof(fileFilteredToken_);
        this.fileFilteredToken_.size = 64;
        this.fileFilteredToken_.ttl = 30;
    }

    /// Activate logging of cache events.
    void enableLog() {
        import std.traits : FieldNameTuple;

        static foreach (m; FieldNameTuple!(typeof(this))) {
            {
                static if (is(typeof(__traits(getMember, this, m)) == CacheLRU!(U, W), U, W))
                    __traits(getMember, this, m).enableCacheEvents;
            }
        }
        enableLog_ = true;
    }

    /// Dumps the cache events to the log.
    private void logEvents() {
        import std.traits : FieldNameTuple;

        if (!enableLog_)
            return;

        static foreach (m; FieldNameTuple!(typeof(this))) {
            {
                static if (is(typeof(__traits(getMember, this, m)) == CacheLRU!(U, W), U, W))
                    foreach (const e; __traits(getMember, this, m).cacheEvents) {
                        logger.trace(m, ": ", e);
                    }
            }
        }
    }

    /** Calculate the checksum for the file content.
     */
    Checksum getFileChecksum(AbsolutePath p, const(ubyte)[] data) {
        typeof(return) rval;
        auto query = file_.get(p);
        if (query.isNull) {
            rval = checksum(data);
            file_.put(p, rval);
        } else {
            rval = query.get;
        }

        debug logEvents;

        return rval;
    }

    /** Calculate the checksum of the file path.
     */
    Checksum getPathChecksum(Path p) {
        typeof(return) rval;
        auto query = path_.get(p);
        if (query.isNull) {
            rval = checksum(cast(const(ubyte)[]) p.payload);
            path_.put(p, rval);
        } else {
            rval = query.get;
        }

        debug logEvents;

        return rval;
    }

    /** Returns: the files content converted to tokens.
     */
    Token[] getTokens(AbsolutePath p, TokenStream tstream) {
        typeof(return) rval;
        auto query = fileToken_.get(p);
        if (query.isNull) {
            rval = tstream.getTokens(p);
            fileToken_.put(p, rval);
        } else {
            rval = query.get;
        }

        debug logEvents;

        return rval;
    }

    /** Returns: the files content converted to tokens.
     */
    Token[] getFilteredTokens(AbsolutePath p, TokenStream tstream) {
        typeof(return) rval;
        auto query = fileFilteredToken_.get(p);
        if (query.isNull) {
            rval = tstream.getFilteredTokens(p);
            fileFilteredToken_.put(p, rval);
        } else {
            rval = query.get;
        }

        debug logEvents;

        return rval;
    }
}
