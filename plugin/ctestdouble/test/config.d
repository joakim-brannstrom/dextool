/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.config;

import dextool_test.types;

enum globalTestdir = "c_tests";
enum xmlLog = "test_double_log.xml";

Path testData() {
    return Path("testdata/cstub");
}
