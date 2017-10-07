/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module ut_main;

int main(string[] args) {
    import std.stdio : writeln;
    import unit_threaded.runner;

    writeln("Running unit tests");
    //dfmt off
    return args.runTests!(
                          "llvm_hiwrap.ast.tree",
                          "llvm_hiwrap.value.basic_block",
                          "llvm_hiwrap.value.function_",
                          "llvm_hiwrap.io",
                          "llvm_hiwrap.llvm_io",
                          "llvm_hiwrap.module_",
                          );
    //dfmt on
}
