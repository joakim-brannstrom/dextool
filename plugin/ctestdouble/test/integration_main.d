/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
import scriptlike;

int main(string[] args) {
    import unit_threaded.runner;
    import std.stdio;

    writeln(`Running integration suite`);
    // dfmt off
    return args.runTests!(
                          "dextool_test.compilation_database_integration",
                          "dextool_test.integration",
                          "dextool_test.xml_files",
                          );
    // dfmt on
}
