/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

A PID regulator and low pass filter.

# Theory

Velocity PID controller from the Laplace transform
U(s) / E(s) = Kp(1 + 1/(Ti*s) + Td*s)
to time domain with backward-difference
u(t) = u(t-1) + Kp(e(t) - e(t-1) + e(t)*Ts/Ti + (e(t) - 2e(t-1) + e(t-2))*Td/Ts)

This is the second form of the classical PID equation.
It is called noninteractive or parallel or ideal or ISA.

Source: http://straightlinecontrol.com/pid_algorithms.html

## SECOND FORM OF THE PID ALGORITHM

The second form of the algorithm is called "noninteracting, or "parallel" or
"ideal" or "ISA" . I understand one manufacturer refers to this as
"interacting", which serves to illustrate that terms by themselves may not
tell you what the algorithm is. This form is used in most textbooks, I
understand. I think it is unfortunate that textbooks do not at least
recognize the different forms. Most if not all books written for industry
users rather than students recognize at least the first two forms. The basic
difference between the first and second forms is in the way derivative is
handled. If the derivative term is set to zero, then the two algorithms are
identical. Since derivative is not used very often (and shouldn't be used
very often) perhaps it is not important to focus on the difference. But it
is important to anyone using derivative, and people who use derivative
should know what they are doing. The parameters set in this form can be made
equivalent (except for the treatment of gain-limiting on derivative) to
those in the first form in this way:

Kc' = ((Ti +Td)/Ti))Kc, "effective" gain.
Ti' = Ti + Td, "effective" integral or reset time
Td' = TiTd/(Ti + Td), "effective" derivative time

These conversions are made by equating the coefficients of s. Conversions in
the reverse direction are:

Kc = FKc'
Ti = FTi'
Td = Td'/F

where

F =0.5 + sqrt(0.25 - Td'/Ti')

Typically Ti is set about 4 to 8 times Td, so the conversion factor is not
huge, but it is important to not loose sight of the correction. With this
algorithm it is possible to have very troublesome combinations of Ti' and
Td'. If Ti'<4Td' then the reset and derivative times, as differentiated from
settings, become complex numbers, which can confuse tuning. Don't slip into
these settings inadvertently! A very knowledgeable tuner may be able to take
advantage of that characteristic in very special cases, but it is not for
everyone, every day. Some companies advise to use the interacting form if
available, simply to avoid that potential pitfall.

This algorithm also has no provision for limiting high frequency gain from
derivative action, a virtually essential feature. In the first algorithm Kd
is typically fixed at 10, or if adjustable, should typically be set
somewhere in the range of 6 to 10. This desirable limiting of the derivative
component is sometimes accomplished in this second form by writing it as:

Kc'(1 + 1/Ti's + Td's)/(1 + Td's/Kd)

or

Kc'(1 + 1/Ti's + Td's/(1 + Td's/Kd))

There are likely many variations on the theme.

The variables Kc', Ti' and Td' have been called "effective". In the Bode
plot, IF Ti'>4Td', THEN Kc' is the minimum frequency-dependent gain (Kc is a
frequency-independent gain). This is at a frequency which is midway between
the "corners" defined by Ti and Td, which is also midway between the
"effective " corners associated with Ti' and Td'. Ti' is always larger than
Ti and Td' is always smaller than Td, which recognizes the slight spreading
of the "effective" corners of the Bode plot as they approach each other.

This algorithm is also called the "ISA" algorithm. The ISA has no
association with this algorithm. Apparently this attribution got started
when someone working on the Fieldbus thought it would become "THE"
algorithm. It didn't. Or hasn't. ANSI/ISA-S51.1-1979 (Rev. 1993) is a
standard on Process Instrumentation Terminology. While this is a standard on
terminology, not algorithms, it uses the first form of the algorithm for
examples and in its Bode plot for a PID controller. Another term used to
identify this algorithm is "ideal". Think of this word as one to identify
the algorithm, not describe it. It is true that it can do everything the
first form can do, and more, provided the gain for derivative is handled
appropriately. But settings which produce complex roots should be used only
by the very knowledgeable.

## THE FIRST FORM OF THE PID ALGORITHM

This first form is called "series" or "interacting" or "analog" or
"classical". The variables are:

Kc = controller gain = 100/proportional band
Ti = Integral or reset time = 1/reset rate in repeats/time
Td = derivative time
Kd = derivative gain

Early pneumatic controllers were probably designed more to meet mechanical
and patent constraints than by a zeal to achieve a certain algorithm. Later
pneumatic controllers tended to have an algorithm close to this first form.
Electronic controllers of major vendors tended to use this algorithm. It is
what process industry control users were used to at the time. If you are
unsure what algorithm is being used for the controller you are tuning, find
out what it is before you start to tune.

I did not follow closely the evolution of algorithms as digital controllers
were introduced. It is my understanding that most major vendors of digital
controllers provide this algorithm as basic, and many provide the second
form as well. Also, many provide several variations (I'm told Allen-Bradley
has 10, and that other manufacturers are adding variations continually).

The choice of the word interacting is interesting. At least one author says
that it is interacting in the time domain and noninteracting in the
frequency domain. Another author disagrees with this distinction. This
really becomes a discussion of what interacts with what. To be safe, think
of the word interacting as one to identify the algorithm, not to describe
it.
*/
module my.signal_theory.pid;

import core.time : dur, Duration;

@safe:

/** A discrete position PID controller.
 *
 * Implemented internally using floating point to simplify the code. Change to
 * fixed point precision if so desired.
 */
struct PositionPid {
    /**
     * Params:
     *  Kp = the propotional gain constant
     *  Ki = the integrating gain constant
     *  Kd = the derivating gain constant
     */
    this(double Kp, double Ki, double Kd) {
        this.Kp = Kp;
        this.Ki = Ki;
        this.Kd = Kd;
    }

    /** Uses the input values to adjust the output.
     *
     * Params:
     *  pv = the measured value/Process Variable.
     */
    void input(double pv) {
        import std.algorithm : clamp;

        // the error between the current output and desired
        double e = sv - pv;

        integral = (integral + e) * Ki;
        integral = clamp(integral, integral_low, integral_high);

        // derivative on measurement, eliminate spikes when sv changes.
        double derivative = 0;
        if (useDFilter) {
            dFilter.input(e - prev_e);
            derivative = Kd * dFilter.output;
        } else {
            derivative = Kd * (e - prev_e);
        }

        output_ = Kp * e + integral + derivative;
        output_ = clamp(output_, output_low, output_high);

        prev_e = e;
    }

    /// Returns: the calculated output gain.
    double output() const {
        return output_;
    }

    /** Set value.
     *
     * The regulator is trying to keep this value
     */
    void setSv(double x) {
        sv = x;
    }

    double getSv() const {
        return sv;
    }

    /// Proportional gain.
    void setKp(double x) {
        Kp = x;
    }

    /// Integral gain.
    void setKi(double x) {
        Ki = x;
    }

    /// Derivative gain.
    void setKd(double x) {
        Kd = x;
    }

    void setKd(LowPassFilter lp) {
        dFilter = lp;
        useDFilter = true;
    }

    /// Clamps the integration to the range [low, high].
    void setIntegralClamp(double low, double high)
    in (low < high) {
        integral_low = low;
        integral_high = high;
    }

    /// Clamps the PID control output to the range [low, high].
    void setOutputClamp(double low, double high)
    in (low < high) {
        output_low = low;
        output_high = high;
    }

    /// Resets the controllers state to initial.
    void reset() {
        this = typeof(this).init;
    }

    import std.range : isOutputRange;

    string toString() const {
        import std.array : appender;

        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        import std.format : formattedWrite;

        formattedWrite(w, "PositionPid(Kp:%s Ki:%s Kd:%s sv:%s integral:%s prev_e:%s output:%s",
                Kp, Ki, Kd, sv, integral, prev_e, output);
    }

private:
    /// previous errors (t-1, t-2)
    double prev_e = 0;

    /// The output value
    double output_ = 0;

    /// The setpoint value the PID is trying to reach
    double sv = 0;

    /// Constaint gain.
    double Kp = 0;
    /// Integral gain.
    double Ki = 0;
    /// Derivative gain.
    double Kd = 0;

    /// Track error over time.
    double integral = 0;

    /// filter to use for the derivative
    LowPassFilter dFilter;
    bool useDFilter;

    /// Clamp of the integral.
    double integral_low = double.min_10_exp;
    double integral_high = double.max_10_exp;

    /// Clamp of the output.
    double output_low = double.min_10_exp;
    double output_high = double.max_10_exp;
};

@("shall instantiate a PositionPid")
unittest {
    import std.stdio : writefln, writeln;
    import my.signal_theory.simulate;

    Simulator sim;

    const period = sim.period;
    const double ticks = cast(double) 1.dur!"seconds"
        .total!"nsecs" / cast(double) period.total!"nsecs";
    const clamp = period.total!"nsecs" / 2;

    const double kp = 0.1;
    const double ki = 0.125;

    auto pid = PositionPid(kp, ki, 4);
    pid.setIntegralClamp(-clamp, clamp);
    pid.setOutputClamp(-clamp, clamp);
    pid.setKd(LowPassFilter(1, 10));

    while (sim.currTime < 1000.dur!"msecs") {
        sim.tick!("nsecs")(a => pid.input(a.total!"nsecs"), () => pid.output);
        if (sim.updated) {
            const diff = sim.targetTime - sim.wakeupTime;
            //writefln!"time[%s] pv[%s] diff[%s] output:%0.2f"(sim.currTime, sim.pv, diff, pid.output);
            //writeln(pid);
        }
    }

    import std.math : abs;

    assert(abs(sim.pv.total!"msecs") < 100);
    assert(abs(pid.output) < 10000.0);
}

/// A first order low pass filter.
struct LowPassFilter {
    /**
     * Params:
     *  dt = time interval
     *  RC = time constant
     */
    this(double dt, double RC) {
        this.dt = dt;
        alpha = dt / (RC + dt);
    }

    void input(double x) {
        y = alpha * x + (1.0 - alpha) * y;
    }

    double output() {
        return y;
    }

private:
    double dt = 1;
    double alpha = 0;
    double y = 0;
};
