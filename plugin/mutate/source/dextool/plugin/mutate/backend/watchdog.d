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

import logger = std.experimental.logger;

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
        st = State.active;
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

/** Watchdog that signal *timeout* after a static time.
 *
 * Progressive watchdog
 */
struct ProgressivWatchdog {
nothrow:
private:
    static immutable double constant_factor = 1.5;
    static immutable double scale_factor = 2.0;

    Duration base_timeout;
    double n = 0;

public:
    this(Duration timeout) {
        this.base_timeout = timeout;
    }

    void incrTimeout() {
        ++n;
    }

    Duration timeout() {
        import std.math : sqrt;

        double scale = constant_factor + sqrt(n) * scale_factor;
        return (1L + (cast(long)(base_timeout.total!"msecs" * scale))).dur!"msecs";
    }
}

private:

import core.time : dur;

version (unittest) {
    struct FakeWatch {
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
}

@("shall signal timeout when the watch has passed the timeout")
unittest {
    // arrange
    auto wd = StaticTime!FakeWatch(10.dur!"seconds");

    // assert
    wd.isOk.shouldBeTrue;

    wd.start;
    wd.isOk.shouldBeTrue;

    // at the limit so should still be ok
    wd.watch.d = 9.dur!"seconds";
    wd.isOk.shouldBeTrue;

    // just past the limit for a ProgressivWatchdog so should trigger
    wd.watch.d = 11.dur!"seconds";
    wd.isOk.shouldBeFalse;
}

@("shall increment the timeout")
unittest {
    import unit_threaded;

    auto pwd = ProgressivWatchdog(2.dur!"seconds");
    auto wd = StaticTime!FakeWatch(pwd.timeout);

    wd.isOk.shouldBeTrue;

    wd.start;
    wd.isOk.shouldBeTrue;

    // shall be not OK because the timer have just passed the timeout
    wd.watch.d = 5.dur!"seconds";
    wd.isOk.shouldBeFalse;

    // arrange
    pwd.incrTimeout;
    wd = StaticTime!FakeWatch(pwd.timeout);

    // assert
    wd.isOk.shouldBeTrue;

    // shall be OK because it is just at the timeout
    wd.watch.d = 6.dur!"seconds";
    wd.isOk.shouldBeTrue;

    // shall trigger because it just passed the timeout
    wd.watch.d = 8.dur!"seconds";
    wd.isOk.shouldBeFalse;
}
