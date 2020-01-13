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

    // TODO: rename to isOpen.
    /// If the channel is open.
    bool hasData() @safe;

    // TODO: rename to hasData.
    /** If there is data to read, non blocking.
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

    /// Close the write channel.
    void closeWrite() @safe;
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

    override void destroy() @safe {
        input.destroy;
        output.destroy;
        outputError.destroy;
    }

    override bool hasData() @safe {
        return input.hasData;
    }

    /// If there is data to read.
    override bool hasPendingData() @safe {
        return input.hasPendingData;
    }

    /** Read at most `s` bytes from the channel.
     *
     * Note that this is slow because the data is copied to keep the interface
     * memory safe. Prefer the one that takes an OutputRange.
     */
    override const(ubyte)[] read(const size_t s) return scope @safe {
        return input.read(s);
    }

    override void write(scope const(ubyte)[] data) @safe {
        output.write(data);
    }

    /// Flush the output.
    override void flush() @safe {
        output.flush;
    }

    override void closeWrite() @safe {
        output.closeWrite;
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

    override void destroy() @trusted {
        input.destroy;
        output.destroy;
    }

    override bool hasData() @safe {
        return input.hasData;
    }

    /// If there is data to read.
    override bool hasPendingData() @safe {
        return input.hasPendingData;
    }

    /** Read at most `s` bytes from the channel.
     *
     * Note that this is slow because the data is copied to keep the interface
     * memory safe. Prefer the one that takes an OutputRange.
     */
    override const(ubyte)[] read(const size_t s) return scope @safe {
        return input.read(s);
    }

    override void write(scope const(ubyte)[] data) @safe {
        output.write(data);
    }

    /// Flush the output.
    override void flush() @safe {
        output.flush;
    }

    override void closeWrite() @safe {
        output.closeWrite;
    }
}

/** A read channel over a `File` object.
 */
class FileReadChannel : ReadChannel {
    private {
        File in_;
        bool eof;
    }

    this(File in_) @trusted {
        this.in_ = in_;
    }

    override void destroy() @safe {
        in_.detach;
    }

    override bool hasData() @safe {
        return !eof;
    }

    override bool hasPendingData() @safe {
        import core.sys.posix.poll;

        pollfd[1] fds;
        fds[0].fd = in_.fileno;
        fds[0].events = POLLIN;
        auto ready = () @trusted { return poll(&fds[0], 1, 0); }();

        if (ready <= 0) {
            return false;
        }
        return (fds[0].revents & POLLIN) != 0;
    }

    override const(ubyte)[] read(const size_t size) return scope @trusted {
        static import core.sys.posix.unistd;

        if (size == 0 || !hasPendingData) {
            return null;
        }

        auto buffer = new ubyte[size];
        auto res = core.sys.posix.unistd.read(in_.fileno, &buffer[0], size);
        if (res <= 0) {
            eof = true;
            return null;
        }

        return cast(const(ubyte)[]) buffer[0 .. res];
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

    override void destroy() @safe {
        out_.detach;
    }

    /** Write data to the output channel.
     *
     * Throws:
     * ErrnoException if the file is not opened or if the call to fwrite fails.
     */
    override void write(scope const(ubyte)[] data) @safe {
        out_.rawWrite(data);
    }

    override void flush() @safe {
        out_.flush();
    }

    override void closeWrite() @safe {
        out_.close;
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
