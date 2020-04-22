/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.gc;

import std.concurrency;
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
        bool isRunning;
        Tid bg;
    }

    ~this() @trusted {
        if (!isRunning)
            return;
        scope (exit)
            isRunning = false;
        send(bg, Msg.stop);
    }

    /** Start a background thread to do the work.
     *
     * It terminates when the destructor is called.
     */
    void start() @trusted {
        scope (success)
            isRunning = true;
        bg = spawn(&tick);
    }

}

private:

enum Msg {
    stop,
}

void tick() nothrow {
    import core.thread : Thread;
    import core.time : dur;
    import core.memory : GC;

    const tickInterval = 1.dur!"minutes";

    bool running = true;
    SysTime next = Clock.currTime + tickInterval;
    while (running) {
        try {
            receiveTimeout(tickInterval, (Msg x) { running = false; });
        } catch (Exception e) {
            running = false;
        }

        GC.collect;
        GC.minimize;
        malloc_trim(0);
    }
}

// malloc_trim - release free memory from the heap
extern (C) int malloc_trim(size_t pad) nothrow @system;
