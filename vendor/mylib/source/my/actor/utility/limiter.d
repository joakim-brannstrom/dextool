/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

An actor that can limit the flow of messages between consumer/producer.

The limiter is initialized with a number of tokens.

Producers try and take a token from the limiter. Either one is free and they
get it right away or a promise is returned. The promise will trigger whenever
a token is returned by the consumre.  The waiting producers are triggered in
LIFO (just because that is a more efficient data structure).

A consumer receiver a message from a producer containing the token and data.
When the consumer has finished processing the message it returns the token to
the limier.
*/
module my.actor.utility.limiter;

import std.array : empty;
import std.typecons : Tuple, tuple;

import my.actor.actor;
import my.actor.typed;
import my.actor.msg;
import my.gc.refc;

/// A token of work.
struct Token {
}

/// Take a token if there are any free.
struct TakeTokenMsg {
}

/// Return a token.
struct ReturnTokenMsg {
}

private struct RefreshMsg {
}

alias FlowControlActor = typedActor!(Token function(TakeTokenMsg),
        void function(ReturnTokenMsg), void function(RefreshMsg));

/// Initialize the flow controller to total cpu's + 1.
FlowControlActor.Impl spawnFlowControlTotalCPUs(FlowControlActor.Impl self) {
    import std.parallelism : totalCPUs;

    return spawnFlowControl(self, totalCPUs + 1);
}

FlowControlActor.Impl spawnFlowControl(FlowControlActor.Impl self, const uint tokens) {
    static struct State {
        uint tokens;
        Promise!Token[] takeReq;
    }

    self.name = "limiter";
    auto st = tuple!("self", "state")(self, refCounted(State(tokens)));
    alias CT = typeof(st);

    static RequestResult!Token takeMsg(ref CT ctx, TakeTokenMsg) {
        typeof(return) rval;

        if (ctx.state.get.tokens > 0) {
            ctx.state.get.tokens--;
            rval = typeof(return)(Token.init);
        } else {
            auto p = makePromise!Token;
            ctx.state.get.takeReq ~= p;
            rval = typeof(return)(p);
        }
        return rval;
    }

    static void returnMsg(ref CT ctx, ReturnTokenMsg) {
        ctx.state.get.tokens++;
        send(ctx.self, RefreshMsg.init);
    }

    static void refreshMsg(ref CT ctx, RefreshMsg) {
        while (ctx.state.get.tokens > 0 && !ctx.state.get.takeReq.empty) {
            ctx.state.get.tokens--;
            ctx.state.get.takeReq[$ - 1].deliver(Token.init);
            ctx.state.get.takeReq = ctx.state.get.takeReq[0 .. $ - 1];
        }

        // extra caution to refresh in case something is missed.
        delayedSend(ctx.self, delay(50.dur!"msecs"), RefreshMsg.init);
    }

    return impl(self, &takeMsg, capture(st), &returnMsg, capture(st), &refreshMsg, capture(st));
}

@("shall limit the message rate of senders by using a limiter to control the flow")
unittest {
    import core.thread : Thread;
    import core.time : dur;
    import std.datetime.stopwatch : StopWatch, AutoStart;
    import my.actor.system;

    auto sys = makeSystem;

    auto limiter = sys.spawn(&spawnFlowControl, 40);

    immutable SenderRate = 1.dur!"msecs";
    immutable ReaderRate = 100.dur!"msecs";

    static struct Tick {
    }

    WeakAddress[] senders;
    foreach (_; 0 .. 100) {
        static struct State {
            WeakAddress recv;
            FlowControlActor.Address limiter;
        }

        static struct SendMsg {
        }

        senders ~= sys.spawn((Actor* self) {
            auto st = tuple!("self", "state")(self, refCounted(State(WeakAddress.init, limiter)));
            alias CT = typeof(st);

            return build(self).set((ref CT ctx, WeakAddress recv) {
                ctx.state.get.recv = recv;
                send(ctx.self.address, Tick.init);
            }, capture(st)).set((ref CT ctx, Tick _) {
                ctx.self.request(ctx.state.get.limiter, infTimeout)
                .send(TakeTokenMsg.init).capture(ctx).then((ref CT ctx, Token t) {
                    send(ctx.self, Tick.init);
                    send(ctx.state.get.recv, t, 42);
                });
            }, capture(st)).finalize;
        });
    }

    auto counter = refCounted(0);
    auto consumer = sys.spawn((Actor* self) {
        auto st = tuple!("self", "limiter", "count")(self, limiter, counter);
        alias CT = typeof(st);

        return impl(self, (ref CT ctx, Tick _) {
            if (ctx.count.get == 100)
                ctx.self.shutdown;
            else
                delayedSend(ctx.self, delay(100.dur!"msecs"), Tick.init);
        }, capture(st), (ref CT ctx, Token t, int _) {
            delayedSend(ctx.limiter, delay(100.dur!"msecs"), ReturnTokenMsg.init);
            ctx.count.get++;
            send(ctx.self, Tick.init);
        }, capture(st));
    });

    foreach (s; senders)
        s.linkTo(consumer);
    limiter.linkTo(consumer);

    auto sw = StopWatch(AutoStart.yes);
    foreach (s; senders)
        send(s, consumer);

    while (counter.get < 100 && sw.peek < 4.dur!"seconds") {
        Thread.sleep(1.dur!"msecs");
    }

    assert(counter.get >= 100);
    // 40 tokens mean that it will trigger at least two "slowdown" which is at least 200 ms.
    assert(sw.peek > 200.dur!"msecs");
}
