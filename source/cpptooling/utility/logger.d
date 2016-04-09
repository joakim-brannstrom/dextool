// Written in the D programming language.
/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.utility.logger;

version (unittest) {
    import unit_threaded : Name, shouldEqual;

public:
} else {
    struct Name {
        string name_;
    }
}

auto errorf(T...)(auto ref T args) nothrow {
    static import std.experimental.logger;

    try {
        std.experimental.logger.errorf(args);
    }
    catch (Exception ex) {
    }
}
