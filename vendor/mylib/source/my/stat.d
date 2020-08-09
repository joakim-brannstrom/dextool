/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This module contains some simple statistics functionality. It isn't intended to
be a full blown stat packaged, that is
[mir](http://mir-algorithm.libmir.org/mir_math_stat.html). I wrote this module
because I had problem using **mir** and only needed a small subset of the
functionality.

The functions probably contain rounding errors etc so be aware. But it seems to
work well enough for simple needs.
*/
module my.stat;

import logger = std.experimental.logger;
import std;
import std.array : appender;
import std.ascii : newline;
import std.format : formattedWrite;
import std.range : isOutputRange, put;

@safe:

/// Example:
unittest {
    auto d0 = [3, 14, 18, 24, 29].makeData;

    writeln(basicStat(d0));

    writeln(histogram(d0, 3));
    writeln(histogram(d0, 3).toBar);

    auto d1 = pdf(NormDistribution(0, 1)).take(10000).makeData;
    writeln(basicStat(d1));
    writeln(stdError(d1));

    auto hist = histogram(d1, 21);
    writeln(hist.toBar);
    writeln(hist.mode);

    writeln(cdf(NormDistribution(0, 1), 1) - cdf(NormDistribution(0, 1), -1));
}

struct StatData {
    double[] value;

    size_t length() {
        return value.length;
    }
}

/// Convert user data to a representation useful for simple, statistics calculations.
StatData makeData(T)(T raw) {
    import std.algorithm;

    double[] r = raw.map!(a => cast(double) a).array;
    if (r.length <= 1)
        throw new Exception("Too few samples");
    return StatData(r);
}

struct Mean {
    double value;
}

Mean mean(StatData data) {
    const N = cast(double) data.length;
    return Mean(data.value.sum / N);
}

/// According to wikipedia this is the Corrected Sample Standard Deviation
struct SampleStdDev {
    double value;
}

SampleStdDev sampleStdDev(StatData data, Mean mean) {
    const N = cast(double) data.length;
    const s = data.value.map!(a => pow(a - mean.value, 2.0)).sum;
    return SampleStdDev(sqrt(s / (N - 1.0)));
}

struct Median {
    double value;
}

Median median(StatData data_) {
    const data = data_.value.sort.map!(a => cast(double) a).array;

    if (data.length % 2 == 0)
        return Median((data[$ / 2 - 1] + data[$ / 2]) / 2.0);
    return Median(data[$ / 2]);
}

struct Histogram {
    long[] buckets;
    double low;
    double high;
    double interval;

    this(double low, double high, long nrBuckets)
    in (nrBuckets > 1, "failed nrBuckets > 1")
    in (low < high, "failed low < high") {
        this.low = low;
        this.high = high;
        interval = (high - low) / cast(double) nrBuckets;
        buckets = iota(0, cast(long) ceil((high - low) / interval)).map!(a => 0L).array;
    }

    void put(const double v)
    in (v >= low && v <= high, "v must be in the range [low, high]") {
        const idx = cast(long) floor((v - low) / interval);
        assert(idx >= 0);

        if (idx < buckets.length)
            buckets[idx] += 1;
        else
            buckets[$ - 1] += 1;
    }

    string toString() @safe const {
        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        import std.range : put;

        formattedWrite(w, "Histogram(low:%s, high:%s, interval:%s, buckets: [",
                low, high, interval);
        foreach (const i; 0 .. buckets.length) {
            if (i != 0)
                put(w, ", ");
            formattedWrite(w, "[%s, %s]:%s", (low + i * interval),
                    (low + (i + 1) * interval), buckets[i]);
        }
        put(w, "])");
    }

    string toBar() @safe const {
        auto buf = appender!string;
        toBar(buf);
        return buf.data;
    }

    void toBar(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        import std.range : put;
        import std.range : repeat;

        immutable maxWidth = 42;
        const fit = () {
            const m = maxElement(buckets);
            if (m > maxWidth)
                return cast(double) m / cast(double) maxWidth;
            return 1.0;
        }();

        const indexWidth = cast(int) ceil(log10(buckets.length) + 1);

        foreach (const i; 0 .. buckets.length) {
            const row = format("[%.3f, %.3f]", (low + i * interval), (low + (i + 1) * interval));
            formattedWrite(w, "%*s %30s: %-(%s%) %s", indexWidth, i, row,
                    repeat("#", cast(size_t)(buckets[i] / fit)), buckets[i]);
            put(w, newline);
        }
    }
}

Histogram histogram(StatData data, long nrBuckets) {
    auto hist = () {
        double low = data.value[0];
        double high = data.value[0];
        foreach (const v; data.value) {
            low = min(low, v);
            high = max(high, v);
        }
        return Histogram(low, high, nrBuckets);
    }();

    foreach (const v; data.value)
        hist.put(v);

    return hist;
}

struct Mode {
    double value;
}

Mode mode(Histogram hist) {
    long cnt = hist.buckets[0];
    double rval = hist.low;
    foreach (const i; 1 .. hist.buckets.length) {
        if (hist.buckets[i] > cnt) {
            rval = hist.low + (i + 0.5) * hist.interval;
            cnt = hist.buckets[i];
        }
    }

    return Mode(rval);
}

struct BasicStat {
    Mean mean;
    Median median;
    SampleStdDev sd;

    string toString() @safe const {
        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        formattedWrite(w, "BasicStat(mean:%s, median:%s, stdev: %s)",
                mean.value, median.value, sd.value);
    }
}

BasicStat basicStat(StatData data) {
    auto m = mean(data);
    return BasicStat(m, median(data), sampleStdDev(data, m));
}

struct NormDistribution {
    double mean;
    double sd;
}

/// From the C++ standard library implementation.
struct NormalDistributionPdf {
    NormDistribution nd;
    private double front_;
    private double V;
    private bool Vhot;

    double front() @safe pure nothrow {
        assert(!empty, "Can't get front of an empty range");
        return front_;
    }

    void popFront() @safe {
        assert(!empty, "Can't pop front of an empty range");

        import std.random : uniform;

        double Up;

        if (Vhot) {
            Vhot = false;
            Up = V;
        } else {
            double u;
            double v;
            double s;

            do {
                u = uniform(-1.0, 1.0);
                v = uniform(-1.0, 1.0);
                s = u * u + v * v;
            }
            while (s > 1 || s == 0);

            double Fp = sqrt(-2.0 * log(s) / s);
            V = v * Fp;
            Vhot = true;
            Up = u * Fp;
        }
        front_ = Up * nd.sd + nd.mean;
    }

    enum bool empty = false;
}

NormalDistributionPdf pdf(NormDistribution nd) {
    auto rval = NormalDistributionPdf(nd);
    rval.popFront;
    return rval;
}

double cdf(NormDistribution nd, double x)
in (nd.sd > 0, "domain error") {
    if (isInfinity(x)) {
        if (x < 0)
            return 0;
        return 1;
    }

    const diff = (x - nd.mean) / (nd.sd * SQRT2);

    return cast(double) erfc(-diff) / 2.0;
}

struct StdMeanError {
    double value;
}

StdMeanError stdError(StatData data)
in (data.value.length > 1) {
    const len = data.value.length;
    double[] means;
    long samples = max(30, data.value.length);
    for (; samples > 0; --samples) {
        means ~= bootstrap(data).sum / cast(double) len;
    }

    return StdMeanError(sampleStdDev(StatData(means), StatData(means).mean).value);
}

auto bootstrap(StatData data, long minSamples = 5)
in (minSamples > 0)
in (data.value.length > 1) {
    const len = data.value.length;
    return iota(min(minSamples, len)).map!(a => uniform(0, len - 1))
        .map!(a => data.value[a]);
}
