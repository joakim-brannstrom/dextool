/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file contains functional *watchdog*s.
*/
module dextool.plugin.mutate.backend.watchdog;

version (unittest) {
    import unit_threaded : shouldEqual, shouldBeFalse, shouldBeTrue;
}

import core.time : Duration;

@safe:

/** Watchdog that signal *timeout* after a static time.
 */
struct StaticTime(WatchT) {
private:
    import std.datetime.stopwatch : StopWatch;

    enum State {
        // watchdog must be initialized before it can be used
        initialize,
        // waiting to be activated
        waiting,
        // it is activate
        active,
        // the timeout has occured
        timeout,
        // finished with no problem
        done,

    }

    State st;
    Duration timeout;
    WatchT watch;

public:
    this(Duration timeout) {
        st = State.waiting;
        this.timeout = timeout;
    }

    // Start the watchdog.
    void start() {
        import std.algorithm : among;

        assert(st.among(State.waiting, State.done));
        watch.start;
    }

    /// Stop the watchdog.
    void stop() {
        assert(st == State.active);
        st = State.done;
        watch.stop;
    }

    /// The timeout has not trigged.
    bool isOk() {
        if (watch.peek > timeout) {
            st = State.timeout;
        }

        return st != State.timeout;
    }
}

private:

import core.time : dur;

@("shall signal timeout when the watch has passed the timeout")
unittest {
    // arrange
    static struct FakeWatch {
        Duration d;
        void start() {
        }

        void stop() {
        }

        void reset() {
        }

        auto peek() {
            return d;
        }
    }

    // act
    auto wd = StaticTime!FakeWatch(10.dur!"seconds");
    // assert
    wd.isOk.shouldBeTrue;

    // act
    wd.start;
    // assert
    wd.isOk.shouldBeTrue;

    // act
    wd.watch.d = 9.dur!"seconds";
    // assert
    wd.isOk.shouldBeTrue;

    // act
    wd.watch.d = 11.dur!"seconds";
    // assert
    wd.isOk.shouldBeFalse;
}
