/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.exception;

import std.format : format;

class ErrorLevelException : Exception {
    int status;

    this(int status, string msg) {
        super(msg);
        this.status = status;
    }

    override string toString() @safe const {
        return format("exit status: %s\n%s", status, msg);
    }
}
