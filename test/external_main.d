/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/

import scriptlike;

int main(string[] args) {
    import unit_threaded.runner;
    import std.stdio;
    import std.file : exists, mkdirRecurse;
    import std.process;
    import std.string : toStringz;
    import utils : buildArtifacts, gmockLib;

    mkdirRecurse(buildArtifacts.toString);

    if (!exists(gmockLib.toString)) {
        scope (exit)
            tryRemove(buildArtifacts ~ "gmock_gtest.o");
        scope (exit)
            tryRemove(buildArtifacts ~ "gmock_main.o");
        scope (failure)
            tryRemove(gmockLib);

        execute(["g++", "fused_gmock/main.cc", "-c", "-o",
                (buildArtifacts ~ "gmock_main.o").toString, "-Ifused_gmock/"]);
        execute(["g++", "fused_gmock/gmock-gtest-all.cc", "-c", "-o",
                (buildArtifacts ~ "gmock_gtest.o").toString, "-Ifused_gmock/"]);
        execute(["ar", "rvs", gmockLib.toString, (buildArtifacts ~ "gmock_gtest.o")
                .toString, (buildArtifacts ~ "gmock_main.o").toString,]);
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
