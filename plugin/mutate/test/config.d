/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This file contains static configuration data for testing the cpptestdouble
plugin.
*/
module dextool_test.config;

enum globalTestdir = "mutate_tests";

auto testData() {
    import scriptlike : Path, absolutePath;

    return Path("plugin_testdata").absolutePath;
}

immutable defaultDb = "database.sqlite3";

string workDir() {
    import std.path;

    return absolutePath("../../..").buildNormalizedPath;
}
