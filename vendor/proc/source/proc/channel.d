/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module proc.channel;

import logger = std.experimental.logger;
import std.stdio : File;

/** Pipes to use to communicate with a process.
 *
 * Can be used to directly communicate via stdin/stdout if so is desired.
 */
struct Pipe {
    FileReadChannel input;
    FileWriteChannel output;

    this(File input, File output) @safe {
        this.input = FileReadChannel(input);
        this.output = FileWriteChannel(output);
    }

    bool isOpen() @safe {
        return input.isOpen;
    }

    /// If there is data to read.
    bool hasPendingData() @safe {
        return input.hasPendingData;
    }

    const(ubyte)[] read(const size_t s) return scope @safe {
        return input.read(s);
    }

    ubyte[] read(ref ubyte[] buf) @safe {
        return input.read(buf);
    }

    void write(scope const(ubyte)[] data) @safe {
        output.write(data);
    }

    void flush() @safe {
        output.flush;
    }

    void closeWrite() @safe {
        output.closeWrite;
    }
}

/** A read channel over a `File` object.
 */
struct FileReadChannel {
    private {
        File in_;
        enum State {
            active,
            hup,
            eof
        }

        State st;
    }

    this(File in_) @trusted {
        this.in_ = in_;
    }

    /// If the channel is open.
    bool isOpen() @safe {
        return st != State.eof;
    }

    /** If there is data to read, non blocking.
     *
     * If this is called before read then it is guaranteed that read will not
     * block.
     */
    bool hasPendingData() @safe {
        import core.sys.posix.poll;

        if (st == State.eof) {
            return false;
        } else if (st == State.hup) {
            // will never block and transition to eof when out of data.
            return true;
        }

        pollfd[1] fds;
        fds[0].fd = in_.fileno;
        fds[0].events = POLLIN;
        auto ready = () @trusted { return poll(&fds[0], 1, 0); }();

        // timeout triggered
        if (ready == 0) {
            return false;
        }

        if (ready < 0) {
            import core.stdc.errno : errno, EINTR;

            if (errno == EINTR) {
                // poll just interrupted. try again.
                return false;
            }

            // an errnor occured.
            st = State.eof;
            return false;
        }

        if (fds[0].revents & POLLHUP) {
            // POLLHUP mean that the other side has been closed. A read will
            // always succeed. If the read returns zero length then it means
            // that the pipe is out of data. Thus the worst thing that happens
            // is that we get nothing, an empty slice.
            st = State.hup;
            return true;
        }

        if (fds[0].revents & (POLLNVAL | POLLERR)) {
            st = State.eof;
            return false;
        }

        return (fds[0].revents & POLLIN) != 0;
    }

    /** Read at most `s` bytes from the channel.
     *
     * Note that this is slow because the data is copied to keep the interface
     * memory safe. Prefer the one that takes a buffer
     */
    const(ubyte)[] read(const size_t size) return scope @safe {
        auto buffer = new ubyte[size];
        return cast(const(ubyte)[]) this.read(buffer);
    }

    /** Read at most `s` bytes from the channel.
     *
     * The data is written directly to buf.
     * The lengt of buf determines how much is read.
     *
     * buf is not resized. Use the returned value.
     */
    ubyte[] read(ref ubyte[] buf) return scope @trusted {
        static import core.sys.posix.unistd;

        if (st == State.eof || buf.length == 0) {
            return null;
        }

        const res = core.sys.posix.unistd.read(in_.fileno, &buf[0], buf.length);
        if (res <= 0) {
            st = State.eof;
            return null;
        }

        return buf[0 .. res];
    }
}

/** IO channel via `File` objects.
 *
 * Useful when e.g. communicating over pipes.
 */
struct FileWriteChannel {
    private File out_;

    this(File out__) @safe {
        out_ = out__;
    }

    /** Write data to the output channel.
     *
     * Throws:
     * ErrnoException if the file is not opened or if the call to fwrite fails.
     */
    void write(scope const(ubyte)[] data) @safe {
        out_.rawWrite(data);
    }

    /// Flush the output.
    void flush() @safe {
        out_.flush();
    }

    /// Close the write channel.
    void closeWrite() @safe {
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
