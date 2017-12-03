/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.interface_;

import std.exception : collectException;
import std.stdio : File;
import logger = std.experimental.logger;

import dextool.type : AbsolutePath;

@safe:

/** Validate source code locations for analyze and mutation.
 */
interface ValidateLoc {
    /// Returns: if a path should be analyzed for mutation points.
    bool shouldAnalyze(AbsolutePath p);

    /// ditto
    bool shouldAnalyze(string p);

    /// Returns: if a mutant are allowed to be written to this path.
    bool shouldMutate(AbsolutePath p);
}

/** Filesystem I/O from the backend.
 *
 * The implementation of the interface shall:
 *  ensure all SafeOutput objects are inside the _output directory_.
 *
 * The design is intended to create a clear distinction between output and
 * input. It is to make it easier to do code review and reason about where
 * filesystem output is created.
 */
interface FilesysIO {
    import std.stdio : File;

    // these are here so backend do not need to import std.stdio which makes it
    // easier to review.
    File getDevNull();
    File getStdin();

    ///
    AbsolutePath getOutputDir();

    ///
    SafeOutput makeOutput(AbsolutePath p);

    ///
    SafeInput makeInput(AbsolutePath p);

protected:
    void putFile(AbsolutePath fname, const(ubyte)[] data);
}

struct SafeOutput {
    import std.array : Appender;

    private AbsolutePath fname;
    private FilesysIO fsys;
    private Appender!(ubyte[]) buf;
    private bool is_open;

    @disable this(this);

    this(AbsolutePath fname, FilesysIO fsys) {
        this.fname = fname;
        this.fsys = fsys;
        this.is_open = true;
    }

    ~this() {
        close();
    }

    // trusted: the data is copied therefore it is safe to cast away const.
    void write(T)(inout T data) @trusted if (!is(T == ubyte[])) {
        buf.put(cast(ubyte[]) data);
    }

    void write(T)(inout T data) if (is(T == ubyte[])) {
        buf.put(data);
    }

    void close() {
        if (is_open) {
            fsys.putFile(fname, buf.data);
            buf.clear;
        }
        is_open = false;
    }
}

struct SafeInput {
    private ubyte[] data;

    this(ubyte[] data) {
        this.data = data;
    }

    ubyte[] read() {
        return data;
    }
}
