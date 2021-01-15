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

public import blob_model : Blob;

import dextool.type : AbsolutePath;

@safe:

/// When a Path is outside of the valid locations.
class InvalidPathException : Exception {
    this(string msg, string file = __FILE__, int line = __LINE__) @safe pure nothrow {
        super(msg, file, line);
    }
}

/** Validate source code locations for analyze and mutation.
 */
interface ValidateLoc {
    /// Returns: the root directory that files to be mutated must reside inside
    AbsolutePath getOutputDir() nothrow;

    bool isInsideOutputDir(AbsolutePath p) nothrow;

    /// Returns: if a path should be analyzed for mutation points.
    bool shouldAnalyze(AbsolutePath p);

    /// Returns: if a mutant are allowed to be written to this path.
    bool shouldMutate(AbsolutePath p);

    /// Duplicate the instance,
    ValidateLoc dup();
}

/** Filesystem I/O from the backend.
 *
 * TODO: rename outputDir to workdir. It is the terminology used in git.
 *
 * The implementation of the interface shall:
 *  ensure all SafeOutput objects are inside the _output directory_.
 *
 * The design is intended to create a clear distinction between output and
 * input. It is to make it easier to do code review and reason about where
 * filesystem output is created.
 */
interface FilesysIO {
    import dextool.type : Path;
    import std.stdio : File;

    // these are here so backend do not need to import std.stdio which makes it
    // easier to review.
    File getDevNull();
    File getStdin();

    /// Convert a path to be relative to the root of the filesystem.
    Path toRelativeRoot(Path p);

    /// Convert a path to an absolute path relative to the root.
    AbsolutePath toAbsoluteRoot(Path p);

    /// File output is restricted to this directory
    AbsolutePath getOutputDir() nothrow;

    ///
    SafeOutput makeOutput(AbsolutePath p);

    ///
    Blob makeInput(AbsolutePath p);

    /// Duplicate the instance,
    FilesysIO dup();

protected:
    void putFile(AbsolutePath fname, const(ubyte)[] data);
}

struct SafeOutput {
    import std.array : Appender;

    private AbsolutePath fname;
    private FilesysIO fsys;
    private Appender!(ubyte[]) buf;
    private bool isOpen;

    @disable this(this);

    this(AbsolutePath fname, FilesysIO fsys) {
        this.fname = fname;
        this.fsys = fsys;
        this.isOpen = true;
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

    void write(Blob b) {
        buf.put(b.content);
    }

    void close() {
        if (isOpen) {
            fsys.putFile(fname, buf.data);
            buf.clear;
        }
        isOpen = false;
    }
}
