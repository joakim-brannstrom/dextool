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
                          "dextool_test.mutate_operators",
                          "dextool_test.mutate_token",
                          "dextool_test.mutate_uoi",
                          );
    // dfmt on
}
