/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This file contains wrappers that uses LLVM's API for IO.
These are generally not needed because D's stdlib provide more than adequate
functionality for IO.

These functions are mostly for debugging purpose. To conveniently be able to
compare the output from LLVM with those in llvm_hiwrap.io.
*/
module llvm_hiwrap.llvm_io;

import llvm_hiwrap.module_;

/** Dump a representation of the module to stderr.
 */
void dumpToStdout(ref Module m) @trusted {
    import llvm : LLVMDumpModule;

    LLVMDumpModule(m.lx);
}

/// ditto
void dumpToFile(ref Module m, string file) @trusted {
    import std.string : toStringz;
    import llvm : LLVMWriteBitcodeToFile;

    const(char)* p = file.toStringz;
    LLVMWriteBitcodeToFile(m.lx, p);
}

@("shall be a dump of the module to a file (using llvm)")
unittest {
    import std.file : remove;
    import llvm_hiwrap.llvm_io;

    immutable p = "remove_me_module_dump_llvm.bc";
    scope (exit)
        remove(p);

    auto m = Module("as_file");
    m.dumpToFile(p);
}
