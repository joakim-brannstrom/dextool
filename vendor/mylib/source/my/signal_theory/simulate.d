/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module my.signal_theory.simulate;

import core.time : Duration, dur;

@safe:

struct Simulator {
    import std.random;

    // how much we have drifted from the desired period.
    Duration pv;

    // The current time.
    Duration currTime = 16666667.dur!"nsecs";
    // Simulated length of a tick
    Duration simTick = 100.dur!"nsecs";

    // Last time the PV where updated.
    Duration lastUpdate;

    // Next time the PID should be updated
    Duration wakeupTime = 100.dur!"nsecs";

    // True if the inputFn+outputFn where called.
    bool updated;

    // The desired period.
    Duration period = 16666667.dur!"nsecs";
    // The target time that should be as close as possible to currTime.
    // starting at -2ms simulate a static offset
    Duration targetTime = 14666667.dur!"nsecs";

    double gain0 = 0;

    MinstdRand0 g = MinstdRand0(42);
    double posRn() {
        return uniform01(g);
    }

    double spreadRn() {
        return uniform!"[]"(-1.0, 1.0, g);
    }

    void tick(string TsUnit)(void delegate(Duration) @safe inputFn, double delegate() @safe outputFn) {
        currTime += simTick;
        updated = false;

        if (currTime < wakeupTime)
            return;
        pv = currTime - targetTime;

        inputFn(pv);

        double gain = spreadRn() * period.total!TsUnit / 10000;

        if (posRn > 0.8) {
            gain0 = spreadRn * period.total!TsUnit / 1000;
        }
        gain += gain0;

        // simulate that high frequency jitter only sometimes occur.
        if (posRn > 0.99) {
            gain += posRn * period.total!TsUnit * 0.5;
        }

        double output = outputFn();

        // the output is a time delay and thus can never be negative.
        wakeupTime = currTime + period + (cast(long)(output + gain)).dur!TsUnit;

        lastUpdate = targetTime;
        targetTime += period;
        updated = true;
    }
};
