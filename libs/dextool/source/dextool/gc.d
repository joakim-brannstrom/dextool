/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.gc;

import std.datetime : SysTime, Clock, dur;

/** Reduces the used memory by the GC and free the heap to the OS.
 *
 * To avoid calling this too often the struct have a timer to ensure it is
 * callled at most ones every minute.
 *
 * TODO: maybe add functionality to call it more often when above e.g. 50% memory usage?
 */
struct MemFree {
    private {
        SysTime next;
    }

    void tick() @trusted nothrow {
        const now = Clock.currTime;
        if (now < next) {
            return;
        }

        import core.memory : GC;

        GC.collect;
        GC.minimize;
        malloc_trim(0);

        next = now + 1.dur!"minutes";
    }
}

private:

// malloc_trim - release free memory from the heap
extern (C) int malloc_trim(size_t pad) nothrow @system;
