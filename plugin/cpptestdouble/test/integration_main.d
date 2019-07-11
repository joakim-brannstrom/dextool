/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/

int main(string[] args) {
    import unit_threaded.runner;
    import std.stdio;

    writeln(`Running integration suite`);
    // dfmt off
    return args.runTests!(
                          "dextool_test.integration",
                          "dextool_test.gtest_integration",
                          "dextool_test.stage_1",
                          );
    // dfmt on
}
