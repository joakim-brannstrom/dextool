/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module process.type;

public import core.sys.posix.unistd : pid_t;

struct Pid {
    pid_t value;
    alias value this;
}

struct PidGroup {
    pid_t value;
    alias value this;
}
