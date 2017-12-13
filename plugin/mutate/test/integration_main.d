/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
import scriptlike;

int main(string[] args) {
    import unit_threaded.runner;
    import std.stdio;

    // dfmt off
    return args.runTests!(
                          "dextool_test.mutate_abs",
                          "dextool_test.mutate_aor",
                          "dextool_test.mutate_lcr",
                          "dextool_test.mutate_ror",
                          "dextool_test.mutate_stmt_deletion",
                          "dextool_test.mutate_uoi",
                          "dextool_test.test_analyzer",
                          "dextool_test.test_report",
                          );
    // dfmt on
}
