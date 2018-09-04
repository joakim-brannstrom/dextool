/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file contains a workaround for compiler version 2.082.
It impossible to assign to a Nullable that may have indirections
*/
module dextool.nullable;

static if (__VERSION__ == 2082) {
    struct Nullable(T) {
        T payload;
        bool isNull_ = true;

        bool isNull() @safe pure nothrow const @nogc {
            return isNull_;
        }

        void opAssign(T rhs) {
            isNull_ = false;
            payload = rhs;
        }

        void opAssign(typeof(this) rhs) {
            isNull_ = rhs.isNull_;
            if (!isNull_)
                payload = rhs.payload;
        }

        void nullify() @safe pure nothrow @nogc {
            isNull_ = true;
        }

        ref inout(T) get() inout {
            assert(!isNull_, "is null");
            return payload;
        }

        alias get this;

        T opCast(T)() {
            return payload;
        }
    }
} else {
    public import std.typecons : Nullable;
}
