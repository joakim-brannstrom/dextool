/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
import std.stdio;
import unit_threaded.runner;

int main(string[] args) {
    writeln(`Running unit tests`);
    //dfmt off
    return args.runTests!(
                          "dextool.plugin.mutate.backend.analyze",
                          "dextool.plugin.mutate.backend.diff_parser",
                          "dextool.plugin.mutate.backend.report.html",
                          "dextool.plugin.mutate.backend.test_mutant.ctest_post_analyze",
                          "dextool.plugin.mutate.backend.test_mutant.gtest_post_analyze",
                          "dextool.plugin.mutate.backend.test_mutant.makefile_post_analyze",
                          "dextool.plugin.mutate.backend.type",
                          "dextool.plugin.mutate.backend.watchdog",
                          "dextool.plugin.mutate.frontend.argparser",
                          "process",
                          );
    //dfmt on
}
