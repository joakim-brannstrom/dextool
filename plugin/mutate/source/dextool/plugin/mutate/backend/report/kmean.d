/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This module contains different kinds of report methods and statistical
analyzers of the data gathered in the database.
*/
module dextool.plugin.mutate.backend.report.kmean;

import std.algorithm : map, sum;
import std.array : Appender, empty, array;
import std.datetime : Duration, Clock;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.math : abs;

struct KmeanIterator(T) {
    double tolerance = 0;
    Cluster!T[] clusters;

    // statistics
    int iterations;
    Duration time;

    void fit(T[] data, int maxIterations, Duration maxTime) {
        auto sw = StopWatch(AutoStart.yes);
        const stopAt = Clock.currTime + maxTime;
        double[] prevMean = clusters.map!(a => a.mean).array;

        foreach (const iter; 0 .. maxIterations) {
            foreach (i; 0 .. clusters.length) {
                clusters[i].updateMean;
            }

            foreach (ref a; clusters)
                a.reset;
            foreach (a; data) {
                const bestMatch = () {
                    auto rval = 0L;
                    auto d0 = clusters[rval].distance(a);
                    foreach (i; 1 .. clusters.length) {
                        const d = clusters[i].distance(a);
                        if (d < d0) {
                            rval = i;
                            d0 = d;
                        }
                    }
                    return rval;
                }();
                clusters[bestMatch].put(a);
            }

            bool term = iter > 1;
            if (Clock.currTime < stopAt) {
                foreach (i; 0 .. clusters.length) {
                    if (abs(clusters[i].mean - prevMean[i]) > tolerance)
                        term = false;
                    prevMean[i] = clusters[i].mean;
                }
            }

            if (term)
                break;
            ++iterations;
        }

        time = sw.peek;
    }
}

struct Point {
    double value;

    T opCast(T : double)() pure const nothrow {
        return cast(double) value;
    }

    double distance(Point p) {
        return abs(value - p.value);
    }
}

struct Cluster(T) {
    double mean = 0;
    Appender!(T[]) data;

    void put(T a) {
        data.put(a);
    }

    void reset() {
        data.clear;
    }

    void updateMean() {
        if (data.data.empty)
            return;
        mean = data.data.map!(a => cast(double) a).sum() / cast(double) data.data.length;
    }

    double distance(T a) {
        return abs(mean - cast(double) a);
    }
}
