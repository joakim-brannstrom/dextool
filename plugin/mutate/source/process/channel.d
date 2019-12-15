/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module process.channel;

import std.stdio : stdin, stdout, File;

class ChannelException : Exception {
    ChannelStatus status;

    this(ChannelStatus s) @safe pure nothrow @nogc {
        super(null);
        status = s;
    }

    string toString(ChannelStatus s) @safe pure nothrow const @nogc {
        final switch (s) with (ChannelStatus) {
        case ok:
            return "ok";
        }
    }
}

enum ChannelStatus {
    ok,
}

interface ReadChannel {
    alias OutRange = void delegate(const(ubyte)[] data);

    /// If the channel is open.
    bool hasData() @safe;

    /** If there is data to read.
     *
     * If this is called before read then it is guaranteed that read will not
     * block.
     */
    bool hasPendingData() @safe;

    /** Read at most `s` bytes from the channel.
     *
     * Note that this is slow because the data is copied to keep the interface
     * memory safe. Prefer the one that takes an OutputRange.
     */
    const(ubyte)[] read(const size_t s) @safe;

    /// ditto
    //void read(OutRange r, const size_t s);

    /// Destroy the channel.
    void destroy() @safe;
}

interface WriteChannel {
    /** Writes as much data as possible to the output.
     *
     * Returns: a slice of the data that is left to write.
     */
    void write(scope const(ubyte)[] data) @safe;

    /// Flush the output.
    void flush() @safe;

    /// Destroy the channel.
    void destroy() @safe;
}

interface Channel : ReadChannel, WriteChannel {
    /// Destroy the channel.
    void destroy() @safe;
}

/** Holds stdin/stdout/stderr channels open.
 *
 * Can be used to directly communicate via stdin/stdout if so is desired.
 */
class Stdio : Channel {
    ReadChannel input;
    WriteChannel output;
    WriteChannel outputError;

    this() {
        import std.stdio : stdin, stdout, stderr;

        input = new FileReadChannel(stdin);
        output = new FileWriteChannel(stdout);
        outputError = new FileWriteChannel(stderr);
    }

    void destroy() @safe {
    }

    bool hasData() @safe {
        return input.hasData;
    }

    /// If there is data to read.
    bool hasPendingData() @safe {
        return input.hasPendingData;
    }

    /** Read at most `s` bytes from the channel.
     *
     * Note that this is slow because the data is copied to keep the interface
     * memory safe. Prefer the one that takes an OutputRange.
     */
    const(ubyte)[] read(const size_t s) return scope @safe {
        return input.read(s);
    }

    void write(scope const(ubyte)[] data) @safe {
        output.write(data);
    }

    /// Flush the output.
    void flush() @safe {
        output.flush;
    }
}

/** Pipes to use to communicate with a process.
 *
 * Can be used to directly communicate via stdin/stdout if so is desired.
 */
class Pipe : Channel {
    import std.process : Pipe;

    ReadChannel input;
    WriteChannel output;

    this(File input, File output) @safe {
        this.input = new FileReadChannel(input);
        this.output = new FileWriteChannel(output);
    }

    void destroy() @trusted {
        .destroy(input);
        .destroy(output);
    }

    bool hasData() @safe {
        return input.hasData;
    }

    /// If there is data to read.
    bool hasPendingData() @safe {
        return input.hasPendingData;
    }

    /** Read at most `s` bytes from the channel.
     *
     * Note that this is slow because the data is copied to keep the interface
     * memory safe. Prefer the one that takes an OutputRange.
     */
    const(ubyte)[] read(const size_t s) return scope @safe {
        return input.read(s);
    }

    void write(scope const(ubyte)[] data) @safe {
        output.write(data);
    }

    /// Flush the output.
    void flush() @safe {
        output.flush;
    }
}

/** A read channel over a `File` object.
 */
class FileReadChannel : ReadChannel {
    import std.parallelism : Task, TaskPool;

    private {
        File in_;
        TaskPool pool;
        Task!(readChar, File*)* background;
    }

    this(File in__) @safe {
        in_ = in__;

        pool = new TaskPool(1);
        pool.isDaemon = true;
        startBackground();
    }

    void destroy() @safe {
        pool.stop();
        .destroy(in_);
    }

    bool hasData() @safe {
        return in_.isOpen && !in_.eof;
    }

    bool hasPendingData() @safe {
        import std.exception : ifThrown;

        return background.done.ifThrown!Exception(false);
    }

    const(ubyte)[] read(const size_t size) return scope @trusted {
        if (size == 0) {
            return null;
        }

        auto buffer = new ubyte[size];

        scope (exit) {
            startBackground();
        }

        try {
            buffer[0] = background.yieldForce();
        } catch (Exception e) {
            return hasData() ? in_.rawRead(buffer) : [];
        }

        if (size > 1) {
            buffer = buffer[0 .. in_.rawRead(buffer[1 .. $]).length + 1];
        }

        return buffer.idup;
    }

    private void startBackground() @safe {
        import std.parallelism : task;

        if (hasData()) {
            background = task!readChar(&in_);
            pool.put(background);
        }
    }

    /// ONLY FOR INTERNAL USE.
    static ubyte readChar(File* fin) {
        ubyte[1] buffer;
        auto result = fin.rawRead(buffer);

        if (result.length > 0) {
            return result[0];
        }

        throw new Exception("No input data");
    }
}

/** IO channel via `File` objects.
 *
 * Useful when e.g. communicating over pipes.
 */
class FileWriteChannel : WriteChannel {
    private File out_;

    this(File out__) @safe {
        out_ = out__;
    }

    void destroy() @safe {
        .destroy(out_);
    }

    /** Write data to the output channel.
     *
     * Throws:
     * ErrnoException if the file is not opened or if the call to fwrite fails.
     */
    void write(scope const(ubyte)[] data) @safe {
        out_.rawWrite(data);
    }

    void flush() @safe {
        out_.flush();
    }
}

/// Returns: a `File` object reading from `/dev/null`.
File nullIn() @safe {
    return File("/dev/null", "r");
}

/// Returns: a `File` object writing to `/dev/null`.
File nullOut() @safe {
    return File("/dev/null", "w");
}
