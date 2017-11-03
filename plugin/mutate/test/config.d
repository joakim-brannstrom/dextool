/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This file contains static configuration data for testing the cpptestdouble
plugin.
*/
module dextool_test.config;

import scriptlike : Path, absolutePath;

enum globalTestdir = "mutate_tests";

auto testData() {
    return Path("plugin_testdata").absolutePath;
}
