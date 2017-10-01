/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.config;

import scriptlike : Path, absolutePath;

enum globalTestdir = "cpp_tests";

auto testData() {
    return Path("testdata/cpp").absolutePath;
}

auto pluginTestData() {
    return Path("plugin_testdata").absolutePath;
}
