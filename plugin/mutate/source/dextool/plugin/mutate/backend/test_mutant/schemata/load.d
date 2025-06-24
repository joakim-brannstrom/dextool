/**
Copyright: Copyright (c) Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

A regulator that adjust the "output" variable depending on the load of the
system and the set value. Its purpose is to make sure the system do not overload.
*/
module dextool.plugin.mutate.backend.test_mutant.schemata.load;

import logger = std.experimental.logger;
import std.algorithm : min, max;
import std.datetime : dur;
import std.exception : collectException;
import std.typecons : Tuple, tuple;

import my.actor;
import my.named_type;
import my.gc.refc;

private struct Tick {
}

struct GetCtrlSignal {
}

// Output control signal to the component controlling the load. Range is [-1000, 1000].
alias Output = NamedType!(double, Tag!"Output");

alias TargetLoad = NamedType!(double, Tag!"SetValue");

alias LoadCtrlActor = typedActor!(void function(Tick), Output function(GetCtrlSignal));

auto spawnLoadCtrlActor(LoadCtrlActor.Impl self, TargetLoad setValue) @trusted {
    static struct State {
        LoadController ctrl;
    }

    auto st = tuple!("self", "state")(self, refCounted(State.init));
    alias Ctx = typeof(st);

    st.state.ctrl.setValue = setValue.get;

    static void tick(ref Ctx ctx, Tick _) nothrow {
        import my.libc : getloadavg;

        try {
            delayedSend(ctx.self, delay(5.dur!"seconds"), Tick.init);

            double[3] load;
            const nr = getloadavg(&load[0], 3);
            if (nr >= 1)
                ctx.state.ctrl.tick(load[0]);
        } catch (Exception e) {
            ctx.state.ctrl.output = ctx.state.ctrl.setValue;
        }

        logger.trace("loadctrl output: ", ctx.state.ctrl.output).collectException;
    }

    static auto getCtrlSignal(ref Ctx ctx, GetCtrlSignal _) {
        return ctx.state.ctrl.output.Output;
    }

    send(self, Tick.init);
    return impl(self, st, &tick, &getCtrlSignal);
}

private struct LoadController {
    import my.signal_theory.kalman;

    KalmanFilter kf = KalmanFilter(2.0, 1, 0.05);
    double setValue = 0;
    double output;

    void tick(double load) {
        kf.updateEstimate(load - setValue);
        output = (setValue - kf.currentEstimate).min(1000.0).max(-1000.0);
    }
}

@("shall update the K-filter and adjust after the set value")
unittest {
    import unit_threaded : writelnUt;

    LoadController ctrl;
    ctrl.setValue = 10;

    foreach (l; [10, 11, 14, 14, 14, 12, 11, 9, 8, 7, 8, 9, 10, 10, 10, 10]) {
        writelnUt("== ", l, " ==");
        // simulate one second
        foreach (_; 0 .. 4) {
            ctrl.tick(l);
            writelnUt(ctrl.output);
        }
    }
}
