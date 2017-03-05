/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/

int main(string[] args) {
    import unit_threaded.runner;
    import std.stdio;
    import std.file : exists;
    import std.process;
    import std.string : toStringz;

    auto gmock_gtest = "libgmock_gtest.a";
    if (!exists(gmock_gtest)) {
        execute(["g++", "fused_gmock/main.cc", "-c", "-o", "gmock_main.o", "-Ifused_gmock/"]);
        execute(["g++", "fused_gmock/gmock-gtest-all.cc", "-c", "-o",
                "gmock_gtest.o", "-Ifused_gmock/"]);
        execute(["ar", "rvs", gmock_gtest, "gmock_gtest.o", "gmock_main.o",]);

        scope (exit)
            remove("gmock_gtest.o");
        scope (exit)
            remove("gmock_main.o");

        scope (failure)
            remove(gmock_gtest.toStringz);
    }

    writeln(`Running tests`);
    //dfmt off
    return args.runTests!(
                          "c_tests",
                          "cpp_tests",
                          "plantuml_tests",
                          "graphml_tests",
                          );
    //dfmt on
}
