/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.type;

/** Prefix used for prepending generated code with a unique string to avoid
 * name collisions.
 * See specific functions for how it is used.
 */
struct StubPrefix {
    string payload;
    alias payload this;
}

/// Prefix used for prepending generated files.
struct FilePrefix {
    string payload;
    alias payload this;
}

struct MainFileName {
    string payload;
    alias payload this;
}

struct MainName {
    string payload;
    alias payload this;
}

struct MainNs {
    string payload;
    alias payload this;
}

struct MainInterface {
    string payload;
    alias payload this;
}

struct CustomHeader {
    string payload;
    alias payload this;
}
