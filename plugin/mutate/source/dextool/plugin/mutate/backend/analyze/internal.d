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
import std.datetime : dur;

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
    import dextool.cachetools;

    private {
        CacheLRU!(string, Token[]) fileToken_;
        bool enableLog_;
    }

    this() {
        this.fileToken_ = new typeof(fileToken_);
        // guessing that 30s and keeping the last 64 is "good enough".
        // TODO: gather metrics or make it configurable.
        this.fileToken_.size = 64;
        this.fileToken_.ttl = 30.dur!"seconds";
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

    /** Returns: the files content converted to tokens.
     */
    Token[] getTokens(AbsolutePath p, TokenStream tstream) {
        typeof(return) rval = fileToken_.cacheToolsRequire(cast(string) p, {
            return tstream.getTokens(p);
        }());
        debug logEvents;
        return rval;
    }
}
