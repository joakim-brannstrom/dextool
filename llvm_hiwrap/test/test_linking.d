/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This test try to link with llvm, llvm_wrap and libLLVM.so followed by trying to
instantiate the majority of the struct/classes.
*/
module app;

import std.algorithm;
import std.stdio;

import llvm;
import llvm_hiwrap;

import test_utils;

@("shall be an instance of Module")
unittest {
    auto m = Module("foo");
    assert(m.verify.isValid == true);
}

@("shall be a dump of a module to stdout")
unittest {
    import llvm_hiwrap.llvm_io;

    auto m = Module("foo");
    m.dumpToStdout;
}

@("shall stringify a module")
unittest {
    auto m = Module("foo");
    m.toString.writeln;
}

@("shall be an instance of a Context")
unittest {
    auto ctx = Context.make;
    ctx.diagnostic.each!(a => stderr.writeln);
}

@("shall be a module created in a Context")
unittest {
    auto ctx = Context.make;
    auto m = ctx.makeModule("foo");

    assert(ctx.diagnostic.length == 0);
    assert(m.verify.isValid == true);
}

@("shall be a serialized/deserialized module")
unittest {
    auto ctx = Context.make;
    auto m = ctx.makeModule("foo");

    assert(ctx.diagnostic.length == 0);

    auto buf = m.toBuffer;
    assert(buf.length != 0);

    auto m2_result = ctx.makeModule(buf);
    assert(m2_result.isValid);
    assert(ctx.diagnostic.length == 0);

    // ok to unpack and use
    auto m2 = m2_result.value;

    auto res1 = m.toString.removeComments;
    auto res2 = m.toString.removeComments;
    assert(res1 == res2);
}

int main(string[] args) {
    import std.stdio : writeln;
    import unit_threaded.runner;

    writeln("Running linker tests");
    //dfmt off
    return args.runTests!(
                          "app",
                          );
    //dfmt on
}
