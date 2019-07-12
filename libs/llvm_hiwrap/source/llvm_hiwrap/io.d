/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This file contains convenient functionality for reading/writing LLVM bitcode
and IR.
The functions prefer using D's stdlib for IO when possible.
*/
module llvm_hiwrap.io;

import std.stdio : File;
import llvm_hiwrap.module_ : Module;
import llvm_hiwrap.context : Context;

/** Write a LLVM module to the file.
 *
 * The function seems silly. It is mostly for self documenting purpose.
 *
 * NOTE: The file extension should be ".bc".
 * NOTE: I have confirmed that this function produces the same output as if
 * LLVMWriteBitcodeToFile is called. See the unittests further down.
 */
void writeModule(File f, ref Module m) {
    auto buf = m.toBuffer;
    f.rawWrite(buf.slice);
}

@("shall be a dump of the module to a file")
unittest {
    import std.file : remove;

    immutable p = "remove_me_module_dump_phobos.bc";
    scope (exit)
        remove(p);

    auto m = Module("as_file");
    auto f = File(p, "w");
    f.writeModule(m);
}

@("shall be no difference between LLVM IO and when using phobos")
unittest {
    import std.file;
    import llvm_hiwrap.llvm_io;

    // arrange
    immutable llvm_io_output = "remove_me_llmv_io_output.bc";
    immutable hiwrap_io_output = "remove_me_hiwrap_io_output.bc";
    auto test_module = Module("test");

    // act
    test_module.dumpToFile(llvm_io_output);
    scope (exit)
        remove(llvm_io_output);

    File(hiwrap_io_output, "w").writeModule(test_module);
    scope (exit)
        remove(hiwrap_io_output);

    // assert
    ubyte[] llvm_io_data = cast(ubyte[]) std.file.read(llvm_io_output);
    ubyte[] hiwrap_io_data = cast(ubyte[]) std.file.read(hiwrap_io_output);

    assert(llvm_io_data == hiwrap_io_data);
}

/** Read a LLVM module from the file.
 *
 */
auto readModule(File f, ref Context ctx, string module_id = null) {
    import llvm_hiwrap.buffer;

    ubyte[1024] buf;
    ubyte[] raw_data;
    raw_data.reserve(1024);

    {
        ubyte[] read_bytes;
        do {
            read_bytes = f.rawRead(buf);
            raw_data ~= read_bytes;
        }
        while (read_bytes.length != 0);
    }

    auto llvm_buf = MemoryBuffer.fromMemory(raw_data, module_id);

    return ctx.makeModule(llvm_buf);
}

@("the written file shall be equivalent to the original when read back (serialize/deserialize)")
unittest {
    import std.file;
    import llvm_hiwrap.context;
    import test_utils;

    // arrange
    auto ctx = Context.make;
    auto test_module = ctx.makeModule("foo");

    immutable test_module_output = "remove_me_test_module_file.bc";
    File(test_module_output, "w").writeModule(test_module);
    scope (exit)
        remove(test_module_output);

    // act
    auto read_module = File(test_module_output).readModule(ctx, "foo");

    // assert
    assert(read_module.isValid);

    auto extracted_read_module = read_module.value;

    auto original_as_txt = test_module.toString;
    auto read_as_txt = extracted_read_module.toString;

    assert(original_as_txt == read_as_txt);
}
