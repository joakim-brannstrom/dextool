/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This file contains data structure to handle LLVM Memory Buffers.
*/
module llvm_hiwrap.buffer;

import llvm_hiwrap.types : LxMessage;
import llvm_hiwrap.util : toD;

struct MemoryBuffer {
    import std.string : toStringz;
    import llvm;

    LLVMMemoryBufferRef lx;

    // TODO move to llvm_hiwrap.llvm_io
    static BufferFromFileResult fromFile(string path) {
        LLVMMemoryBufferRef buf;
        LxMessage msg;

        const(char)* p = path.toStringz;
        LLVMBool success = LLVMCreateMemoryBufferWithContentsOfFile(p, &buf, &msg.rawPtr);
        return BufferFromFileResult(MemoryBuffer(buf), success == 0, msg.toD);
    }

    static MemoryBufferFromMemory fromMemory(const(ubyte)[] region, string buffer_name) {
        const(char)* name = buffer_name.toStringz;
        LLVMMemoryBufferRef buf = LLVMCreateMemoryBufferWithMemoryRange(
                cast(const(char)*) region.ptr, region.length, name, LLVMBool(false));
        return MemoryBufferFromMemory(region, MemoryBuffer(buf));
    }

    static MemoryBuffer fromMemoryCopy(const(ubyte)[] region, string buffer_name) {
        const(char)* name = buffer_name.toStringz;
        LLVMMemoryBufferRef buf = LLVMCreateMemoryBufferWithMemoryRangeCopy(
                cast(const(char)*) region.ptr, region.length, name);
        return MemoryBuffer(buf);
    }

    @disable this(this);

    ~this() {
        LLVMDisposeMemoryBuffer(lx);
    }

    size_t length() {
        return LLVMGetBufferSize(lx);
    }

    const(ubyte)[] slice() {
        const(ubyte)* begin = cast(const(ubyte)*) LLVMGetBufferStart(lx);
        return begin[0 .. this.length];
    }
}

struct MemoryBufferFromMemory {
    // Keep a reference around to the memory in case it is allocated by the GC.
    private const(ubyte)[] region;

    MemoryBuffer buffer;
    alias buffer this;

    @disable this(this);
}

private:

struct BufferFromFileResult {
    private MemoryBuffer value_;
    bool isValid;
    string errorMsg;

    MemoryBuffer value() {
        assert(isValid);
        auto lx = value_.lx;
        value_.lx = null;
        return MemoryBuffer(lx);
    }
}
