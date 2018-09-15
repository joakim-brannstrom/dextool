/**
Copyright: Copyright (c) 2016-2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Abstractions merging in-memory *file like objects" with memory mapped files.

In in-memory *file like objects* abstraction.
Objects are read-only.

They can be either constructed from files on the filesystem or from memory.
*/
module dextool.vfs;

import std.traits : isSomeString;
import std.typecons : Flag, Yes, No;
import logger = std.experimental.logger;

public import dextool.type : FileName;

/**
 * TODO use DIP-1000 to implement slices that do not escape the scope.
 */
@safe struct VfsFile {
    import std.typecons : NullableRef;

    private static struct Impl {
        VirtualFileSystem.RefCntMem* mem;

        bool isInitialized() @safe pure nothrow const @nogc {
            return mem !is null;
        }
    }

    private Impl* payload;
    private NullableRef!VirtualFileSystem owner;

    this(NullableRef!VirtualFileSystem owner, VirtualFileSystem.RefCntMem* a) {
        this.payload = new Impl(a);
        this.owner = owner;
    }

    this(this) {
        if (!payload.isInitialized)
            return;
        ++payload.mem.count;
    }

    ~this() nothrow @nogc {
        if (!payload.isInitialized)
            return;

        --payload.mem.count;
    }

    size_t length() @safe pure nothrow const @nogc {
        assert(payload.isInitialized);
        return payload.mem.data.length;
    }

    void opAssign(typeof(this) rhs) {
        import std.algorithm : swap;

        swap(payload, rhs.payload);
    }

    ubyte opIndexAssign(ubyte value, size_t i) {
        assert(payload.isInitialized);
        return payload.mem.data[i] = value;
    }

    ubyte opIndex(size_t i) {
        assert(payload.isInitialized);
        return payload.mem.data[i];
    }

    ubyte[] opSlice() @safe pure nothrow @nogc {
        assert(payload.isInitialized);
        return payload.mem.data;
    }

    ubyte[] opSlice(size_t begin, size_t end) @safe pure nothrow @nogc {
        assert(payload.isInitialized);
        assert(end <= opDollar);

        return payload.mem.data[begin .. end];
    }

    size_t opDollar() @safe pure nothrow const @nogc {
        return this.length;
    }

    void write(const(ubyte)[] content) {
        assert(payload.isInitialized);

        payload.mem.data ~= content;
    }

    void write(string content) @safe {
        this.write(trustedCast!(ubyte[])(content));
    }

    void clear() @safe {
        this.payload.mem.data = this.payload.mem.data[0 .. 0];
    }

    // Note: it is NOT safe to return a string because the buffer mutates if
    // the file on disk is changed.
    scope const(char)[] toChars() @safe {
        import std.utf : validate;

        auto data = this.opSlice();

        auto result = trustedCast!(const(char)[])(data);
        validate(result);
        return result;
    }

    private static auto trustedCast(T0, T1)(T1 buf) @trusted {
        return cast(T0) buf;
    }
}

/** File layer abstracting the handling of in-memory files and concrete
 * filesystem files.
 *
 * This struct abstracts and contains those differences.
 *
 * The lookup rule for a filename is:
 *  - in-memory container.
 *  - load from the filesystem.
 */
struct VirtualFileSystem {
    import std.typecons : nullableRef;

    private {
        struct RefCntMem {
            ubyte[] data;
            size_t count;

            this(bool dummy) @safe pure nothrow {
                this.count = 1;
            }
        }

        // enables *fast* reverse mapping of a ptr to its filename.
        // must be kept in sync with files_ and filesys
        FileName[RefCntMem* ] rev_files;

        RefCntMem*[FileName] files_;
    }

    // The VFS is expected to be "static". A pointer to an object is always valid.
    // The VFS is "heavy", forbid movement.
    @disable this(this);

    /** Release all resources held by the VFS.
     *
     * But this is so far a minor problem that is partially mitigated by
     * disabling the postblit. This mean that the VFS commonly have a lifetime
     * that is longer than the users of the slices.
     */
    void release() @trusted nothrow {
        files_.clear;
        rev_files.clear;
    }

    /** Add a mapping to a concrete file.
     *
     * Params:
     *   fname = file to map into the VFS
     */
    VfsFile open(FileName fname) @safe {
        if (auto v = fname in files_) {
            (*v).count += 1;
            return VfsFile(nullableRef(&this), *v);
        }

        static import std.file;

        auto mem = new RefCntMem(false);
        mem.data = () @trusted{ return cast(ubyte[]) std.file.read(fname); }();

        files_[fname] = mem;
        rev_files[mem] = fname;

        return VfsFile(nullableRef(&this), mem);
    }

    /** Create an in-memory file.
     *
     * Params:
     *   fname = simulated in-memory filename.
     */
    VfsFile openInMemory(FileName fname) @safe {
        if (auto v = fname in files_) {
            (*v).count += 1;
            return VfsFile(nullableRef(&this), *v);
        }

        auto mem = new RefCntMem(false);
        files_[fname] = mem;
        rev_files[mem] = fname;
        return VfsFile(nullableRef(&this), mem);
    }

    private void close(FileName fname) @safe nothrow @nogc {
        if (auto v = fname in files_) {
            rev_files.remove(*v);
            files_.remove(fname);
        }
    }

    /**
     * Trusted on the assumption that byKey is @safe _enough_.
     *
     * Returns: range of the filenames in the VFS.
     */
    auto files() @trusted pure nothrow const @nogc {
        return rev_files.byValue;
    }
}

version (unittest) {
    import unit_threaded : shouldEqual;
}

@("shall be an in-memory mapped file")
@safe unittest {
    VirtualFileSystem vfs;
    string code = "some code";
    auto filename = FileName("path/to/code.c");

    auto f = vfs.openInMemory(filename);
    f.write(code);

    f.toChars.shouldEqual(code);

    () @trusted{
        f[].shouldEqual(cast(ubyte[]) code);
        f[0].shouldEqual(cast(ubyte) 's');
        f[1 .. 3].shouldEqual(cast(ubyte[]) "om");
        f[5 .. $].shouldEqual(cast(ubyte[]) "code");

        string write_val = "smurf";
        auto buf = f[4 .. $];
        buf[] = cast(ubyte[]) write_val;
        f[4 .. $].shouldEqual(cast(ubyte[]) "smurf");
    }();
}

@("shall be a file from the filesystem")
unittest {
    import std.string : toStringz;
    import std.stdio;
    import std.random : uniform;
    import std.conv : to;

    VirtualFileSystem vfs;
    string code = "content of fun.txt";

    auto filename = FileName(uniform!size_t.to!string ~ "_test_vfs.txt");
    File(filename, "w").write(code);
    scope (exit)
        remove(filename.toStringz);

    auto f = vfs.open(filename);
    f.toChars.shouldEqual(code);
}
