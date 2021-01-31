/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.types;

public import my.path;

class ErrorLevelException : Exception {
    int exitStatus;

    this(int exitStatus, string msg) {
        super(msg);
        this.exitStatus = exitStatus;
    }
}
