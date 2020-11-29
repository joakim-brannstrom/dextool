/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module my.signal_theory.kalman;

import core.time : Duration, dur;
import std.math : abs;
import std.range : isOutputRange;

@safe:

/// Kalman filter for a unidimensional models.
struct KalmanFilter {
    double currentEstimate = 0;
    double estimateError = 0;
    double kalmanGain = 0;
    double lastEstimate = 0;
    double measurementError = 0;
    double q = 0;

    /**
     * Params:
     *  measurementError = measurement uncertainty. How much the measurements
     *      is expected to vary.
     *  estimationError = estimation uncertainty. Adjusted over time by the
     *      Kalman Filter but can be initialized to mea_e.
     *  q = process variance. usually a small number [0.001, 1]. How fast the
     *      measurement moves. Recommended is 0.001, tune as needed.
     */
    this(double measurementError, double estimateError, double q) {
        this.measurementError = measurementError;
        this.estimateError = estimateError;
        this.q = q;
    }

    void updateEstimate(double mea) {
        kalmanGain = estimateError / (estimateError + measurementError);
        currentEstimate = lastEstimate + kalmanGain * (mea - lastEstimate);
        estimateError = (1.0 - kalmanGain) * estimateError + abs(lastEstimate - currentEstimate) * q;
        lastEstimate = currentEstimate;
    }

    string toString() @safe const {
        import std.array : appender;

        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        import std.format : formattedWrite;

        formattedWrite(w,
                "KalmanFilter(measurementError:%s estimateError:%s q:%s currentEstimate:%s lastEstimate:%s gain:%s",
                measurementError, estimateError, q, currentEstimate, lastEstimate, kalmanGain);
    }
}

@("shall instantiate and run a kalman filter")
unittest {
    import std.stdio : writefln, writeln;
    import my.signal_theory.simulate;

    Simulator sim;

    const period = sim.period;
    const double ticks = cast(double) 1.dur!"seconds"
        .total!"nsecs" / cast(double) period.total!"nsecs";
    const clamp = period.total!"nsecs" / 2;

    auto kf = KalmanFilter(2, 2, 0.01);

    while (sim.currTime < 1000.dur!"msecs") {
        sim.tick!"nsecs"(a => kf.updateEstimate(a.total!"nsecs"), () => -kf.currentEstimate);
        if (sim.updated) {
            const diff = sim.targetTime - sim.wakeupTime;
            //writefln!"time[%s] pv[%s] diff[%s]"(sim.currTime, sim.pv, diff);
            //writeln(kf);
        }
    }

    assert(abs(sim.pv.total!"msecs") < 100);
    assert(abs(kf.currentEstimate) < 18000.0);
}
