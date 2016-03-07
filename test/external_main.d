// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/

int main(string[] args) {
    import unit_threaded.runner;
    import std.stdio;

    writeln(`Running tests`);
    //dfmt off
    return args.runTests!(
                          "cstub_tests",
                          "cpp_tests",
                          );
    //dfmt on
}
