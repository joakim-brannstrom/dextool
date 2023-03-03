/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module my.actor.actor;

import std.stdio : writeln, writefln;

import core.thread : Thread;
import logger = std.experimental.logger;
import std.algorithm : schwartzSort, max, min, among;
import std.array : empty;
import std.datetime : SysTime, Clock, dur;
import std.exception : collectException;
import std.functional : toDelegate;
import std.meta : staticMap;
import std.sumtype;
import std.traits : Parameters, Unqual, ReturnType, isFunctionPointer, isFunction;
import std.typecons : Tuple, tuple;
import std.variant : Variant;

import my.actor.common : ExitReason, SystemError, makeSignature;
import my.actor.mailbox;
import my.actor.msg;
import my.actor.system : System;
import my.actor.typed : isTypedAddress, isTypedActorImpl;
import my.gc.refc;

private struct PromiseData {
    WeakAddress replyTo;
    ulong replyId;

    /// Copy constructor
    this(ref return scope typeof(this) rhs) @safe nothrow @nogc {
        replyTo = rhs.replyTo;
        replyId = rhs.replyId;
    }

    @disable this(this);
}

// deliver can only be called one time.
struct Promise(T) {
    package {
        RefCounted!PromiseData data;
    }

    void deliver(T reply) {
        auto tmp = reply;
        deliver(reply);
    }

    /** Deliver the message `reply`.
     *
     * A promise can only be delivered once.
     */
    void deliver(ref T reply) @trusted
    in (!data.empty, "promise must be initialized") {
        if (data.empty)
            return;
        scope (exit)
            data.release;

        // TODO: should probably call delivering actor with an ErrorMsg if replyTo is closed.
        if (auto replyTo = data.get.replyTo.lock.get) {
            enum wrapInTuple = !is(T : Tuple!U, U);
            static if (wrapInTuple)
                replyTo.put(Reply(data.get.replyId, Variant(tuple(reply))));
            else
                replyTo.put(Reply(data.get.replyId, Variant(reply)));
        }
    }

    void opAssign(Promise!T rhs) {
        data = rhs.data;
    }

    /// True if the promise is not initialized.
    bool empty() {
        return data.empty || data.get.replyId == 0;
    }

    /// Clear the promise.
    void clear() {
        data.release;
    }
}

auto makePromise(T)() {
    return Promise!T(refCounted(PromiseData.init));
}

struct RequestResult(T) {
    this(T v) {
        value = typeof(value)(v);
    }

    this(ErrorMsg v) {
        value = typeof(value)(v);
    }

    this(Promise!T v) {
        value = typeof(value)(v);
    }

    SumType!(T, ErrorMsg, Promise!T) value;
}

private alias MsgHandler = void delegate(void* ctx, ref Variant msg) @safe;
private alias RequestHandler = void delegate(void* ctx, ref Variant msg,
        ulong replyId, WeakAddress replyTo) @safe;
private alias ReplyHandler = void delegate(void* ctx, ref Variant msg) @safe;

alias DefaultHandler = void delegate(ref Actor self, ref Variant msg) @safe nothrow;

/** Actors send error messages to others by returning an error (see Errors)
 * from a message handler. Similar to exit messages, error messages usually
 * cause the receiving actor to terminate, unless a custom handler was
 * installed. The default handler is used as fallback if request is used
 * without error handler.
 */
alias ErrorHandler = void delegate(ref Actor self, ErrorMsg) @safe nothrow;

/** Bidirectional monitoring with a strong lifetime coupling is established by
 * calling a `LinkRequest` to an address. This will cause the runtime to send
 * an `ExitMsg` if either this or other dies. Per default, actors terminate
 * after receiving an `ExitMsg` unless the exit reason is exit_reason::normal.
 * This mechanism propagates failure states in an actor system. Linked actors
 * form a sub system in which an error causes all actors to fail collectively.
 */
alias ExitHandler = void delegate(ref Actor self, ExitMsg msg) @safe nothrow;

/// An exception has been thrown while processing a message.
alias ExceptionHandler = void delegate(ref Actor self, Exception e) @safe nothrow;

/** Actors can monitor the lifetime of other actors by sending a `MonitorRequest`
 * to an address. This will cause the runtime system to send a `DownMsg` for
 * other if it dies.
 *
 * Actors drop down messages unless they provide a custom handler.
 */
alias DownHandler = void delegate(ref Actor self, DownMsg msg) @safe nothrow;

void defaultHandler(ref Actor self, ref Variant msg) @safe nothrow {
}

/// Write the name of the actor and the message type to the console.
void logAndDropHandler(ref Actor self, ref Variant msg) @trusted nothrow {
    import std.stdio : writeln;

    try {
        writeln("UNKNOWN message sent to actor ", self.name);
        writeln(msg.toString);
    } catch (Exception e) {
    }
}

void defaultErrorHandler(ref Actor self, ErrorMsg msg) @safe nothrow {
    self.lastError = msg.reason;
    self.shutdown;
}

void defaultExitHandler(ref Actor self, ExitMsg msg) @safe nothrow {
    self.lastError = msg.reason;
    self.forceShutdown;
}

void defaultExceptionHandler(ref Actor self, Exception e) @safe nothrow {
    self.lastError = SystemError.runtimeError;
    // TODO: should log?
    self.forceShutdown;
}

// Write the name of the actor and the exception to stdout.
void logExceptionHandler(ref Actor self, Exception e) @safe nothrow {
    import std.stdio : writeln;

    self.lastError = SystemError.runtimeError;

    try {
        writeln("EXCEPTION thrown by actor ", self.name);
        writeln(e.msg);
        writeln("TERMINATING");
    } catch (Exception e) {
    }

    self.forceShutdown;
}

/// Timeout for an outstanding request.
struct ReplyHandlerTimeout {
    ulong id;
    SysTime timeout;
}

package enum ActorState {
    /// waiting to be started.
    waiting,
    /// active and processing messages.
    active,
    /// wait for all awaited responses to finish
    shutdown,
    /// discard also the awaite responses, just shutdown fast
    forceShutdown,
    /// in process of shutting down
    finishShutdown,
    /// stopped.
    stopped,
}

private struct AwaitReponse {
    Closure!(ReplyHandler, void*) behavior;
    ErrorHandler onError;
}

struct Actor {
    import std.container.rbtree : RedBlackTree, redBlackTree;

    package StrongAddress addr;
    // visible in the package for logging purpose.
    package ActorState state_ = ActorState.stopped;

    private {
        // TODO: rename to behavior.
        Closure!(MsgHandler, void*)[ulong] incoming;
        Closure!(RequestHandler, void*)[ulong] reqBehavior;

        // callbacks for awaited responses key:ed on their id.
        AwaitReponse[ulong] awaitedResponses;
        ReplyHandlerTimeout[] replyTimeouts;

        // important that it start at 1 because then zero is known to not be initialized.
        ulong nextReplyId = 1;

        /// Delayed messages ordered by their trigger time.
        RedBlackTree!(DelayedMsg*, "a.triggerAt < b.triggerAt", true) delayed;

        /// Used during shutdown to signal monitors and links why this actor is terminating.
        SystemError lastError;

        /// monitoring the actor lifetime.
        WeakAddress[size_t] monitors;

        /// strong, bidirectional link of the actors lifetime.
        WeakAddress[size_t] links;

        // Number of messages that has been processed.
        ulong messages_;

        /// System the actor belongs to.
        System* homeSystem_;

        string name_;

        ErrorHandler errorHandler_;

        /// callback when a link goes down.
        DownHandler downHandler_;

        ExitHandler exitHandler_;

        ExceptionHandler exceptionHandler_;

        DefaultHandler defaultHandler_;
    }

    invariant () {
        if (addr && !state_.among(ActorState.waiting, ActorState.shutdown)) {
            assert(errorHandler_);
            assert(exitHandler_);
            assert(exceptionHandler_);
            assert(defaultHandler_);
        }
    }

    this(StrongAddress a) @trusted
    in (!a.empty, "address is empty") {
        state_ = ActorState.waiting;

        addr = a;
        addr.get.setOpen;
        delayed = new typeof(delayed);

        errorHandler_ = toDelegate(&defaultErrorHandler);
        downHandler_ = null;
        exitHandler_ = toDelegate(&defaultExitHandler);
        exceptionHandler_ = toDelegate(&defaultExceptionHandler);
        defaultHandler_ = toDelegate(&.defaultHandler);
    }

    WeakAddress address() @safe {
        return addr.weakRef;
    }

    package ref StrongAddress addressRef() return @safe pure nothrow @nogc {
        return addr;
    }

    ref System homeSystem() @safe pure nothrow @nogc {
        return *homeSystem_;
    }

    /** Clean shutdown of the actor
     *
     * Stopping incoming messages from triggering new behavior and finish all
     * awaited respones.
     */
    void shutdown() @safe nothrow {
        if (state_.among(ActorState.waiting, ActorState.active))
            state_ = ActorState.shutdown;
    }

    /** Force an immediate shutdown.
     *
     * Stopping incoming messages from triggering new behavior and finish all
     * awaited respones.
     */
    void forceShutdown() @safe nothrow {
        if (state_.among(ActorState.waiting, ActorState.active, ActorState.shutdown))
            state_ = ActorState.forceShutdown;
    }

    ulong id() @safe pure nothrow const @nogc {
        return addr.id;
    }

    /// Returns: the name of the actor.
    string name() @safe pure nothrow const @nogc {
        return name_;
    }

    // dfmt off

    /// Set name name of the actor.
    void name(string n) @safe pure nothrow @nogc {
        this.name_ = n;
    }

    void errorHandler(ErrorHandler v) @safe pure nothrow @nogc {
        errorHandler_ = v;
    }

    void downHandler(DownHandler v) @safe pure nothrow @nogc {
        downHandler_ = v;
    }

    void exitHandler(ExitHandler v) @safe pure nothrow @nogc {
        exitHandler_ = v;
    }

    void exceptionHandler(ExceptionHandler v) @safe pure nothrow @nogc {
        exceptionHandler_ = v;
    }

    void defaultHandler(DefaultHandler v) @safe pure nothrow @nogc {
        defaultHandler_ = v;
    }

    // dfmt on

package:
    bool hasMessage() @safe pure nothrow @nogc {
        return addr && addr.get.hasMessage;
    }

    /// How long until a delayed message or a timeout fires.
    Duration nextTimeout(const SysTime now, const Duration default_) @safe {
        return min(delayed.empty ? default_ : (delayed.front.triggerAt - now),
                replyTimeouts.empty ? default_ : (replyTimeouts[0].timeout - now));
    }

    bool waitingForReply() @safe pure nothrow const @nogc {
        return !awaitedResponses.empty;
    }

    /// Number of messages that has been processed.
    ulong messages() @safe pure nothrow const @nogc {
        return messages_;
    }

    void setHomeSystem(System* sys) @safe pure nothrow @nogc {
        homeSystem_ = sys;
    }

    void cleanupBehavior() @trusted nothrow {
        foreach (ref a; incoming.byValue) {
            try {
                a.free;
            } catch (Exception e) {
                // TODO: call exceptionHandler?
            }
        }
        incoming = null;
        foreach (ref a; reqBehavior.byValue) {
            try {
                a.free;
            } catch (Exception e) {
            }
        }
        reqBehavior = null;
    }

    void cleanupAwait() @trusted nothrow {
        foreach (ref a; awaitedResponses.byValue) {
            try {
                a.behavior.free;
            } catch (Exception e) {
            }
        }
        awaitedResponses = null;
    }

    void cleanupDelayed() @trusted nothrow {
        foreach (const _; 0 .. delayed.length) {
            try {
                delayed.front.msg = Msg.init;
                delayed.removeFront;
            } catch (Exception e) {
            }
        }
        .destroy(delayed);
    }

    bool isAlive() @safe pure nothrow const @nogc {
        final switch (state_) {
        case ActorState.waiting:
            goto case;
        case ActorState.active:
            goto case;
        case ActorState.shutdown:
            goto case;
        case ActorState.forceShutdown:
            goto case;
        case ActorState.finishShutdown:
            return true;
        case ActorState.stopped:
            return false;
        }
    }

    /// Accepting messages.
    bool isAccepting() @safe pure nothrow const @nogc {
        final switch (state_) {
        case ActorState.waiting:
            goto case;
        case ActorState.active:
            goto case;
        case ActorState.shutdown:
            return true;
        case ActorState.forceShutdown:
            goto case;
        case ActorState.finishShutdown:
            goto case;
        case ActorState.stopped:
            return false;
        }
    }

    ulong replyId() @safe {
        return nextReplyId++;
    }

    void process(const SysTime now) @safe nothrow {
        import core.memory : GC;

        assert(!GC.inFinalizer);

        messages_ = 0;

        void tick() {
            // philosophy of the order is that a timeout should only trigger if it
            // is really required thus it is checked last. This order then mean
            // that a request may have triggered a timeout but because
            // `processReply` is called before `checkReplyTimeout` it is *ignored*.
            // Thus "better to accept even if it is timeout rather than fail".
            //
            // NOTE: the assumption that a message that has timed out should be
            // processed turned out to be... wrong. It is annoying that
            // sometimes a timeout message triggers even though it shouldn't,
            // because it is now too old to be useful!
            // Thus the order is changed to first check for timeout, then process.
            try {
                processSystemMsg();
                checkReplyTimeout(now);
                processDelayed(now);
                processIncoming();
                processReply();
            } catch (Exception e) {
                exceptionHandler_(this, e);
            }
        }

        assert(state_ == ActorState.stopped || addr, "no address");

        final switch (state_) {
        case ActorState.waiting:
            state_ = ActorState.active;
            tick;
            // the state can be changed before the actor have executed.
            break;
        case ActorState.active:
            tick;
            // self terminate if the actor has no behavior.
            if (incoming.empty && awaitedResponses.empty && reqBehavior.empty)
                state_ = ActorState.forceShutdown;
            break;
        case ActorState.shutdown:
            tick;
            if (awaitedResponses.empty)
                state_ = ActorState.finishShutdown;
            cleanupBehavior;
            break;
        case ActorState.forceShutdown:
            state_ = ActorState.finishShutdown;
            cleanupBehavior;
            addr.get.setClosed;
            break;
        case ActorState.finishShutdown:
            state_ = ActorState.stopped;

            sendToMonitors(DownMsg(addr.weakRef, lastError));

            sendToLinks(ExitMsg(addr.weakRef, lastError));

            replyTimeouts = null;
            cleanupDelayed;
            cleanupAwait;

            // must be last because sendToLinks and sendToMonitors uses addr.
            addr.get.shutdown();
            addr.release;
            break;
        case ActorState.stopped:
            break;
        }
    }

    void sendToMonitors(DownMsg msg) @safe nothrow {
        foreach (ref a; monitors.byValue) {
            try {
                auto tmp = a.lock;
                auto rc = tmp.get;
                if (rc)
                    rc.put(SystemMsg(msg));
                a.release;
            } catch (Exception e) {
            }
        }

        monitors = null;
    }

    void sendToLinks(ExitMsg msg) @safe nothrow {
        foreach (ref a; links.byValue) {
            try {
                auto tmp = a.lock;
                auto rc = tmp.get;
                if (rc)
                    rc.put(SystemMsg(msg));
                a.release;
            } catch (Exception e) {
            }
        }

        links = null;
    }

    void checkReplyTimeout(const SysTime now) @safe {
        if (replyTimeouts.empty)
            return;

        size_t removeTo;
        foreach (const i; 0 .. replyTimeouts.length) {
            if (now > replyTimeouts[i].timeout) {
                const id = replyTimeouts[i].id;
                if (auto v = id in awaitedResponses) {
                    messages_++;
                    v.onError(this, ErrorMsg(addr.weakRef, SystemError.requestTimeout));
                    try {
                        () @trusted { v.behavior.free; }();
                    } catch (Exception e) {
                    }
                    awaitedResponses.remove(id);
                }
                removeTo = i + 1;
            } else {
                break;
            }
        }

        if (removeTo >= replyTimeouts.length) {
            replyTimeouts = null;
        } else if (removeTo != 0) {
            replyTimeouts = replyTimeouts[removeTo .. $];
        }
    }

    void processIncoming() @safe {
        if (addr.get.empty!Msg)
            return;
        messages_++;

        auto front = addr.get.pop!Msg;
        scope (exit)
            .destroy(front);

        void doSend(ref MsgOneShot msg) {
            if (auto v = front.get.signature in incoming) {
                (*v)(msg.data);
            } else {
                defaultHandler_(this, msg.data);
            }
        }

        void doRequest(ref MsgRequest msg) @trusted {
            if (auto v = front.get.signature in reqBehavior) {
                (*v)(msg.data, msg.replyId, msg.replyTo);
            } else {
                defaultHandler_(this, msg.data);
            }
        }

        front.get.type.match!((ref MsgOneShot a) { doSend(a); }, (ref MsgRequest a) {
            doRequest(a);
        });
    }

    /** All system messages are handled.
     *
     * Assuming:
     *  * they are not heavy to process
     *  * very important that if there are any they should be handled as soon as possible
     *  * ignoring the case when there is a "storm" of system messages which
     *    "could" overload the actor system and lead to a crash. I classify this,
     *    for now, as intentional, malicious coding by the developer themself.
     *    External inputs that could trigger such a behavior should be controlled
     *    and limited. Other types of input such as a developer trying to break
     *    the actor system is out of scope.
     */
    void processSystemMsg() @safe {
        //() @trusted {
        //logger.infof("run %X", cast(void*) &this);
        //}();
        while (!addr.get.empty!SystemMsg) {
            messages_++;
            //logger.infof("%X %s %s", addr.toHash, state_, messages_);
            auto front = addr.get.pop!SystemMsg;
            scope (exit)
                .destroy(front);

            front.get.match!((ref DownMsg a) {
                if (downHandler_)
                    downHandler_(this, a);
            }, (ref MonitorRequest a) { monitors[a.addr.toHash] = a.addr; }, (ref DemonitorRequest a) {
                if (auto v = a.addr.toHash in monitors)
                    v.release;
                monitors.remove(a.addr.toHash);
            }, (ref LinkRequest a) { links[a.addr.toHash] = a.addr; }, (ref UnlinkRequest a) {
                if (auto v = a.addr.toHash in links)
                    v.release;
                links.remove(a.addr.toHash);
            }, (ref ErrorMsg a) { errorHandler_(this, a); }, (ref ExitMsg a) {
                exitHandler_(this, a);
            }, (ref SystemExitMsg a) {
                final switch (a.reason) {
                case ExitReason.normal:
                    break;
                case ExitReason.unhandledException:
                    exitHandler_(this, ExitMsg.init);
                    break;
                case ExitReason.unknown:
                    exitHandler_(this, ExitMsg.init);
                    break;
                case ExitReason.userShutdown:
                    exitHandler_(this, ExitMsg.init);
                    break;
                case ExitReason.kill:
                    exitHandler_(this, ExitMsg.init);
                    // the user do NOT have an option here
                    forceShutdown;
                    break;
                }
            });
        }
    }

    void processReply() @safe {
        if (addr.get.empty!Reply)
            return;
        messages_++;

        auto front = addr.get.pop!Reply;
        scope (exit)
            .destroy(front);

        if (auto v = front.get.id in awaitedResponses) {
            // TODO: reduce the lookups on front.id
            v.behavior(front.get.data);
            try {
                () @trusted { v.behavior.free; }();
            } catch (Exception e) {
            }
            awaitedResponses.remove(front.get.id);
            removeReplyTimeout(front.get.id);
        } else {
            // TODO: should probably be SystemError.unexpectedResponse?
            defaultHandler_(this, front.get.data);
        }
    }

    void processDelayed(const SysTime now) @trusted {
        if (!addr.get.empty!DelayedMsg) {
            // count as a message because handling them are "expensive".
            // Ignoring the case that the message right away is moved to the
            // incoming queue. This lead to "double accounting" but ohh well.
            // Don't use delayedSend when you should have used send.
            messages_++;
            delayed.insert(addr.get.pop!DelayedMsg.unsafeMove);
        } else if (delayed.empty) {
            return;
        }

        foreach (const i; 0 .. delayed.length) {
            if (now > delayed.front.triggerAt) {
                addr.get.put(delayed.front.msg);
                delayed.removeFront;
            } else {
                break;
            }
        }
    }

    private void removeReplyTimeout(ulong id) @safe nothrow {
        import std.algorithm : remove;

        foreach (const i; 0 .. replyTimeouts.length) {
            if (replyTimeouts[i].id == id) {
                remove(replyTimeouts, i);
                break;
            }
        }
    }

    void register(ulong signature, Closure!(MsgHandler, void*) handler) @trusted {
        if (!isAccepting)
            return;

        if (auto v = signature in incoming) {
            try {
                v.free;
            } catch (Exception e) {
            }
        }
        incoming[signature] = handler;
    }

    void register(ulong signature, Closure!(RequestHandler, void*) handler) @trusted {
        if (!isAccepting)
            return;

        if (auto v = signature in reqBehavior) {
            try {
                v.free;
            } catch (Exception e) {
            }
        }
        reqBehavior[signature] = handler;
    }

    void register(ulong replyId, SysTime timeout, Closure!(ReplyHandler,
            void*) reply, ErrorHandler onError) @safe {
        if (!isAccepting)
            return;

        awaitedResponses[replyId] = AwaitReponse(reply, onError is null ? errorHandler_ : onError);
        replyTimeouts ~= ReplyHandlerTimeout(replyId, timeout);
        schwartzSort!(a => a.timeout, (a, b) => a < b)(replyTimeouts);
    }
}

struct Closure(Fn, CtxT) {
    alias FreeFn = void function(CtxT);

    Fn fn;
    CtxT ctx;
    FreeFn cleanup;

    this(Fn fn) {
        this.fn = fn;
    }

    this(Fn fn, CtxT* ctx, FreeFn cleanup) {
        this.fn = fn;
        this.ctx = ctx;
        this.cleanup = cleanup;
    }

    void opCall(Args...)(auto ref Args args) {
        assert(fn !is null);
        fn(ctx, args);
    }

    void free() {
        // will crash, on purpuse, if there is a ctx and no cleanup registered.
        // maybe a bad idea? dunno... lets see
        if (ctx)
            cleanup(ctx);
        ctx = CtxT.init;
    }
}

@("shall register a behavior to be called when msg received matching signature")
unittest {
    auto addr = makeAddress2;
    auto actor = Actor(addr);

    bool processedIncoming;
    void fn(void* ctx, ref Variant msg) {
        processedIncoming = true;
    }

    actor.register(1, Closure!(MsgHandler, void*)(&fn));
    addr.get.put(Msg(1, MsgType(MsgOneShot(Variant(42)))));

    actor.process(Clock.currTime);

    assert(processedIncoming);
}

private void cleanupCtx(CtxT)(void* ctx)
        if (is(CtxT == Tuple!T, T) || is(CtxT == void)) {
    import std.traits;
    import my.actor.typed;

    static if (!is(CtxT == void)) {
        // trust that any use of this also pass on the correct context type.
        auto userCtx = () @trusted { return cast(CtxT*) ctx; }();
        // release the context such as if it holds a rc object.
        alias Types = CtxT.Types;

        static foreach (const i; 0 .. CtxT.Types.length) {
            {
                alias T = CtxT.Types[i];
                alias UT = Unqual!T;
                static if (!is(T == UT)) {
                    static assert(!is(UT : WeakAddress),
                            "WeakAddress must NEVER be const or immutable");
                    static assert(!is(UT : TypedAddress!M, M...),
                            "WeakAddress must NEVER be const or immutable: " ~ T.stringof);
                }
                // TODO: add a -version actor_ctx_diagnostic that prints when it is unable to deinit?

                static if (is(UT == T)) {
                    .destroy((*userCtx)[i]);
                }
            }
        }
    }
}

@("shall default initialize when possible, skipping const/immutable")
unittest {
    {
        auto x = tuple(cast(const) 42, 43);
        alias T = typeof(x);
        cleanupCtx!T(cast(void*)&x);
        assert(x[0] == 42); // can't assign to const
        assert(x[1] == 0);
    }

    {
        import my.path : Path;

        auto x = tuple(Path.init, cast(const) Path("foo"));
        alias T = typeof(x);
        cleanupCtx!T(cast(void*)&x);
        assert(x[0] == Path.init);
        assert(x[1] == Path("foo"));
    }
}

package struct Action {
    Closure!(MsgHandler, void*) action;
    ulong signature;
}

/// An behavior for an actor when it receive a message of `signature`.
package auto makeAction(T, CtxT = void)(T handler) @safe
        if (isFunction!T || isFunctionPointer!T) {
    static if (is(CtxT == void))
        alias Params = Parameters!T;
    else {
        alias CtxParam = Parameters!T[0];
        alias Params = Parameters!T[1 .. $];
        checkMatchingCtx!(CtxParam, CtxT);
        checkRefForContext!handler;
    }

    alias HArgs = staticMap!(Unqual, Params);

    void fn(void* ctx, ref Variant msg) @trusted {
        static if (is(CtxT == void)) {
            handler(msg.get!(Tuple!HArgs).expand);
        } else {
            auto userCtx = cast(CtxParam*) cast(CtxT*) ctx;
            handler(*userCtx, msg.get!(Tuple!HArgs).expand);
        }
    }

    return Action(typeof(Action.action)(&fn, null, &cleanupCtx!CtxT), makeSignature!HArgs);
}

package Closure!(ReplyHandler, void*) makeReply(T, CtxT)(T handler) @safe {
    static if (is(CtxT == void))
        alias Params = Parameters!T;
    else {
        alias CtxParam = Parameters!T[0];
        alias Params = Parameters!T[1 .. $];
        checkMatchingCtx!(CtxParam, CtxT);
        checkRefForContext!handler;
    }

    alias HArgs = staticMap!(Unqual, Params);

    void fn(void* ctx, ref Variant msg) @trusted {
        static if (is(CtxT == void)) {
            handler(msg.get!(Tuple!HArgs).expand);
        } else {
            auto userCtx = cast(CtxParam*) cast(CtxT*) ctx;
            handler(*userCtx, msg.get!(Tuple!HArgs).expand);
        }
    }

    return typeof(return)(&fn, null, &cleanupCtx!CtxT);
}

package struct Request {
    Closure!(RequestHandler, void*) request;
    ulong signature;
}

private string locToString(Loc...)() {
    import std.conv : to;

    return Loc[0] ~ ":" ~ Loc[1].to!string ~ ":" ~ Loc[2].to!string;
}

/// Check that the context parameter is `ref` otherwise issue a warning.
package void checkRefForContext(alias handler)() {
    import std.traits : ParameterStorageClass, ParameterStorageClassTuple;

    alias CtxParam = ParameterStorageClassTuple!(typeof(handler))[0];

    static if (CtxParam != ParameterStorageClass.ref_) {
        pragma(msg, "INFO: handler type is " ~ typeof(handler).stringof);
        static assert(CtxParam == ParameterStorageClass.ref_,
                "The context must be `ref` to avoid unnecessary copying");
    }
}

package void checkMatchingCtx(CtxParam, CtxT)() {
    static if (!is(CtxT == CtxParam)) {
        static assert(__traits(compiles, { auto x = CtxParam(CtxT.init.expand); }),
                "mismatch between the context type " ~ CtxT.stringof
                ~ " and the first parameter " ~ CtxParam.stringof);
    }
}

package auto makeRequest(T, CtxT = void)(T handler) @safe {
    static assert(!is(ReturnType!T == void), "handler returns void, not allowed");

    alias RType = ReturnType!T;
    enum isReqResult = is(RType : RequestResult!ReqT, ReqT);
    enum isPromise = is(RType : Promise!PromT, PromT);

    static if (is(CtxT == void))
        alias Params = Parameters!T;
    else {
        alias CtxParam = Parameters!T[0];
        alias Params = Parameters!T[1 .. $];
        checkMatchingCtx!(CtxParam, CtxT);
        checkRefForContext!handler;
    }

    alias HArgs = staticMap!(Unqual, Params);

    void fn(void* rawCtx, ref Variant msg, ulong replyId, WeakAddress replyTo) @trusted {
        static if (is(CtxT == void)) {
            auto r = handler(msg.get!(Tuple!HArgs).expand);
        } else {
            auto ctx = cast(CtxParam*) cast(CtxT*) rawCtx;
            auto r = handler(*ctx, msg.get!(Tuple!HArgs).expand);
        }

        static if (isReqResult) {
            r.value.match!((ErrorMsg a) { sendSystemMsg(replyTo, a); }, (Promise!ReqT a) {
                assert(!a.data.empty, "the promise MUST be constructed before it is returned");
                a.data.get.replyId = replyId;
                a.data.get.replyTo = replyTo;
            }, (data) {
                enum wrapInTuple = !is(typeof(data) : Tuple!U, U);
                if (auto rc = replyTo.lock.get) {
                    static if (wrapInTuple)
                        rc.put(Reply(replyId, Variant(tuple(data))));
                    else
                        rc.put(Reply(replyId, Variant(data)));
                }
            });
        } else static if (isPromise) {
            r.data.get.replyId = replyId;
            r.data.get.replyTo = replyTo;
        } else {
            // TODO: is this syntax for U one variable or variable. I want it to be variable.
            enum wrapInTuple = !is(RType : Tuple!U, U);
            if (auto rc = replyTo.lock.get) {
                static if (wrapInTuple)
                    rc.put(Reply(replyId, Variant(tuple(r))));
                else
                    rc.put(Reply(replyId, Variant(r)));
            }
        }
    }

    return Request(typeof(Request.request)(&fn, null, &cleanupCtx!CtxT), makeSignature!HArgs);
}

@("shall link two actors lifetime")
unittest {
    int count;
    void countExits(ref Actor self, ExitMsg msg) @safe nothrow {
        count++;
        self.shutdown;
    }

    auto aa1 = Actor(makeAddress2);
    auto a1 = build(&aa1).set((int x) {}).exitHandler_(&countExits).finalize;
    auto aa2 = Actor(makeAddress2);
    auto a2 = build(&aa2).set((int x) {}).exitHandler_(&countExits).finalize;

    a1.linkTo(a2.address);
    a1.process(Clock.currTime);
    a2.process(Clock.currTime);

    assert(a1.isAlive);
    assert(a2.isAlive);

    sendExit(a1.address, ExitReason.userShutdown);
    foreach (_; 0 .. 5) {
        a1.process(Clock.currTime);
        a2.process(Clock.currTime);
    }

    assert(!a1.isAlive);
    assert(!a2.isAlive);
    assert(count == 2);
}

@("shall let one actor monitor the lifetime of the other one")
unittest {
    int count;
    void downMsg(ref Actor self, DownMsg msg) @safe nothrow {
        count++;
    }

    auto aa1 = Actor(makeAddress2);
    auto a1 = build(&aa1).set((int x) {}).downHandler_(&downMsg).finalize;
    auto aa2 = Actor(makeAddress2);
    auto a2 = build(&aa2).set((int x) {}).finalize;

    a1.monitor(a2.address);
    a1.process(Clock.currTime);
    a2.process(Clock.currTime);

    assert(a1.isAlive);
    assert(a2.isAlive);

    sendExit(a2.address, ExitReason.userShutdown);
    foreach (_; 0 .. 5) {
        a1.process(Clock.currTime);
        a2.process(Clock.currTime);
    }

    assert(a1.isAlive);
    assert(!a2.isAlive);
    assert(count == 1);
}

private struct BuildActor {
    Actor* actor;

    Actor* finalize() @safe {
        auto rval = actor;
        actor = null;
        return rval;
    }

    auto errorHandler(ErrorHandler a) {
        actor.errorHandler = a;
        return this;
    }

    auto downHandler_(DownHandler a) {
        actor.downHandler_ = a;
        return this;
    }

    auto exitHandler_(ExitHandler a) {
        actor.exitHandler_ = a;
        return this;
    }

    auto exceptionHandler_(ExceptionHandler a) {
        actor.exceptionHandler_ = a;
        return this;
    }

    auto defaultHandler_(DefaultHandler a) {
        actor.defaultHandler_ = a;
        return this;
    }

    auto set(BehaviorT)(BehaviorT behavior)
            if ((isFunction!BehaviorT || isFunctionPointer!BehaviorT)
                && !is(ReturnType!BehaviorT == void)) {
        auto act = makeRequest(behavior);
        actor.register(act.signature, act.request);
        return this;
    }

    auto set(BehaviorT, CT)(BehaviorT behavior, CT c)
            if ((isFunction!BehaviorT || isFunctionPointer!BehaviorT)
                && !is(ReturnType!BehaviorT == void)) {
        auto act = makeRequest!(BehaviorT, CT)(behavior);
        // for now just use the GC to allocate the context on.
        // TODO: use an allocator.
        act.request.ctx = cast(void*) new CT(c);
        actor.register(act.signature, act.request);
        return this;
    }

    auto set(BehaviorT)(BehaviorT behavior)
            if ((isFunction!BehaviorT || isFunctionPointer!BehaviorT)
                && is(ReturnType!BehaviorT == void)) {
        auto act = makeAction(behavior);
        actor.register(act.signature, act.action);
        return this;
    }

    auto set(BehaviorT, CT)(BehaviorT behavior, CT c)
            if ((isFunction!BehaviorT || isFunctionPointer!BehaviorT)
                && is(ReturnType!BehaviorT == void)) {
        auto act = makeAction!(BehaviorT, CT)(behavior);
        // for now just use the GC to allocate the context on.
        // TODO: use an allocator.
        act.action.ctx = cast(void*) new CT(c);
        actor.register(act.signature, act.action);
        return this;
    }
}

package BuildActor build(Actor* a) @safe {
    return BuildActor(a);
}

/// Implement an actor.
Actor* impl(Behavior...)(Actor* self, Behavior behaviors) {
    import my.actor.msg : isCapture, Capture;

    auto bactor = build(self);
    static foreach (const i; 0 .. Behavior.length) {
        {
            alias b = Behavior[i];

            static if (!isCapture!b) {
                static if (!(isFunction!(b) || isFunctionPointer!(b)))
                    static assert(0, "behavior may only be functions, not delgates: " ~ b.stringof);

                static if (i + 1 < Behavior.length && isCapture!(Behavior[i + 1])) {
                    bactor.set(behaviors[i], behaviors[i + 1]);
                } else
                    bactor.set(behaviors[i]);
            }
        }
    }

    return bactor.finalize;
}

@("build dynamic actor from functions")
unittest {
    static void fn3(int s) @safe {
    }

    static string fn4(int s) @safe {
        return "foo";
    }

    static Tuple!(int, string) fn5(const string s) @safe {
        return typeof(return)(42, "hej");
    }

    auto aa1 = Actor(makeAddress2);
    auto a1 = build(&aa1).set(&fn3).set(&fn4).set(&fn5).finalize;
}

unittest {
    bool delayOk;
    static void fn1(ref Tuple!(bool*, "delayOk") c, const string s) @safe {
        *c.delayOk = true;
    }

    bool delayShouldNeverHappen;
    static void fn2(ref Tuple!(bool*, "delayShouldNeverHappen") c, int s) @safe {
        *c.delayShouldNeverHappen = true;
    }

    auto aa1 = Actor(makeAddress2);
    auto actor = build(&aa1).set(&fn1, capture(&delayOk)).set(&fn2,
            capture(&delayShouldNeverHappen)).finalize;
    delayedSend(actor.address, Clock.currTime - 1.dur!"seconds", "foo");
    delayedSend(actor.address, Clock.currTime + 1.dur!"hours", 42);

    assert(!actor.addressRef.get.empty!DelayedMsg);
    assert(actor.addressRef.get.empty!Msg);
    assert(actor.addressRef.get.empty!Reply);

    actor.process(Clock.currTime);

    assert(!actor.addressRef.get.empty!DelayedMsg);
    assert(actor.addressRef.get.empty!Msg);
    assert(actor.addressRef.get.empty!Reply);

    actor.process(Clock.currTime);
    actor.process(Clock.currTime);

    assert(actor.addressRef.get.empty!DelayedMsg);
    assert(actor.addressRef.get.empty!Msg);
    assert(actor.addressRef.get.empty!Reply);

    assert(delayOk);
    assert(!delayShouldNeverHappen);
}

@("shall process a request->then chain xyz")
@system unittest {
    // checking capture is correctly setup/teardown by using captured rc.

    auto rcReq = refCounted(42);
    bool calledOk;
    static string fn(ref Tuple!(bool*, "calledOk", RefCounted!int) ctx, const string s,
            const string b) {
        assert(2 == ctx[1].refCount);
        if (s == "apa")
            *ctx.calledOk = true;
        return "foo";
    }

    auto rcReply = refCounted(42);
    bool calledReply;
    static void reply(ref Tuple!(bool*, RefCounted!int) ctx, const string s) {
        *ctx[0] = s == "foo";
        assert(2 == ctx[1].refCount);
    }

    auto aa1 = Actor(makeAddress2);
    auto actor = build(&aa1).set(&fn, capture(&calledOk, rcReq)).finalize;

    assert(2 == rcReq.refCount);
    assert(1 == rcReply.refCount);

    actor.request(actor.address, infTimeout).send("apa", "foo")
        .capture(&calledReply, rcReply).then(&reply);
    assert(2 == rcReply.refCount);

    assert(!actor.addr.get.empty!Msg);
    assert(actor.addr.get.empty!Reply);

    actor.process(Clock.currTime);
    assert(actor.addr.get.empty!Msg);
    assert(actor.addr.get.empty!Reply);

    assert(2 == rcReq.refCount);
    assert(1 == rcReply.refCount, "after the message is consumed the refcount should go back");

    assert(calledOk);
    assert(calledReply);

    actor.shutdown;
    while (actor.isAlive)
        actor.process(Clock.currTime);
}

@("shall process a request->then chain using promises")
unittest {
    static struct A {
        string v;
    }

    static struct B {
        string v;
    }

    int calledOk;
    auto fn1p = makePromise!string;
    static RequestResult!string fn1(ref Capture!(int*, "calledOk", Promise!string, "p") c, A a) @trusted {
        if (a.v == "apa")
            (*c.calledOk)++;
        return typeof(return)(c.p);
    }

    auto fn2p = makePromise!string;
    static Promise!string fn2(ref Capture!(int*, "calledOk", Promise!string, "p") c, B a) {
        (*c.calledOk)++;
        return c.p;
    }

    int calledReply;
    static void reply(ref Tuple!(int*) ctx, const string s) {
        if (s == "foo")
            *ctx[0] += 1;
    }

    auto aa1 = Actor(makeAddress2);
    auto actor = build(&aa1).set(&fn1, capture(&calledOk, fn1p)).set(&fn2,
            capture(&calledOk, fn2p)).finalize;

    actor.request(actor.address, infTimeout).send(A("apa")).capture(&calledReply).then(&reply);
    actor.request(actor.address, infTimeout).send(B("apa")).capture(&calledReply).then(&reply);

    actor.process(Clock.currTime);
    assert(calledOk == 1); // first request
    assert(calledReply == 0);

    fn1p.deliver("foo");

    assert(calledReply == 0);

    actor.process(Clock.currTime);
    assert(calledOk == 2); // second request triggered
    assert(calledReply == 1);

    fn2p.deliver("foo");
    actor.process(Clock.currTime);

    assert(calledReply == 2);

    actor.shutdown;
    while (actor.isAlive) {
        actor.process(Clock.currTime);
    }
}

/// The timeout triggered.
class ScopedActorException : Exception {
    this(ScopedActorError err, string file = __FILE__, int line = __LINE__) @safe pure nothrow {
        super(null, file, line);
        error = err;
    }

    ScopedActorError error;
}

enum ScopedActorError : ubyte {
    none,
    // actor address is down
    down,
    // request timeout
    timeout,
    // the address where unable to process the received message
    unknownMsg,
    // some type of fatal error occured.
    fatal,
}

/** Intended to be used in a local scope by a user.
 *
 * `ScopedActor` is not thread safe.
 */
struct ScopedActor {
    import my.actor.typed : underlyingAddress, underlyingWeakAddress;

    private {
        static struct Data {
            Actor self;
            ScopedActorError errSt;

            ~this() @safe {
                if (self.addr.empty)
                    return;

                () @trusted {
                    self.downHandler = null;
                    self.defaultHandler = toDelegate(&.defaultHandler);
                    self.errorHandler = toDelegate(&defaultErrorHandler);
                }();

                self.shutdown;
                while (self.isAlive) {
                    self.process(Clock.currTime);
                }
            }
        }

        RefCounted!Data data;
    }

    this(StrongAddress addr, string name) @safe {
        data = refCounted(Data(Actor(addr)));
        data.get.self.name = name;
    }

    private void reset() @safe nothrow {
        data.get.errSt = ScopedActorError.none;
    }

    SRequestSend request(TAddress)(TAddress requestTo, SysTime timeout)
            if (isAddress!TAddress) {
        reset;
        auto rs = .request(&data.get.self, underlyingWeakAddress(requestTo), timeout);
        return SRequestSend(rs, this);
    }

    private static struct SRequestSend {
        RequestSend rs;
        ScopedActor self;

        /// Copy constructor
        this(ref return typeof(this) rhs) @safe pure nothrow @nogc {
            rs = rhs.rs;
            self = rhs.self;
        }

        @disable this(this);

        SRequestSendThen send(Args...)(auto ref Args args) {
            return SRequestSendThen(.send(rs, args), self);
        }
    }

    private static struct SRequestSendThen {
        RequestSendThen rs;
        ScopedActor self;
        uint backoff;

        /// Copy constructor
        this(ref return typeof(this) rhs) {
            rs = rhs.rs;
            self = rhs.self;
            backoff = rhs.backoff;
        }

        @disable this(this);

        void dynIntervalSleep() @trusted {
            // +100 usecs "feels good", magic number. current OS and
            // implementation of message passing isn't that much faster than
            // 100us. A bit slow behavior, ehum, for a scoped actor is OK. They
            // aren't expected to be used for "time critical" sections.
            Thread.sleep(backoff.dur!"usecs");
            backoff = min(backoff + 100, 20000);
        }

        private static struct ValueCapture {
            RefCounted!Data data;

            void downHandler(ref Actor, DownMsg) @safe nothrow {
                data.get.errSt = ScopedActorError.down;
            }

            void errorHandler(ref Actor, ErrorMsg msg) @safe nothrow {
                if (msg.reason == SystemError.requestTimeout)
                    data.get.errSt = ScopedActorError.timeout;
                else
                    data.get.errSt = ScopedActorError.fatal;
            }

            void unknownMsgHandler(ref Actor a, ref Variant msg) @safe nothrow {
                logAndDropHandler(a, msg);
                data.get.errSt = ScopedActorError.unknownMsg;
            }
        }

        void then(T)(T handler, ErrorHandler onError = null) {
            scope (exit)
                demonitor(rs.rs.self, rs.rs.requestTo);
            monitor(rs.rs.self, rs.rs.requestTo);

            auto callback = new ValueCapture(self.data);
            self.data.get.self.downHandler = &callback.downHandler;
            self.data.get.self.defaultHandler = &callback.unknownMsgHandler;
            self.data.get.self.errorHandler = &callback.errorHandler;

            () @trusted { .thenUnsafe!(T, void)(rs, handler, null, onError); }();

            scope (exit)
                () @trusted {
                self.data.get.self.downHandler = null;
                self.data.get.self.defaultHandler = toDelegate(&.defaultHandler);
                self.data.get.self.errorHandler = toDelegate(&defaultErrorHandler);
            }();

            auto requestTo = rs.rs.requestTo.lock;
            if (!requestTo)
                throw new ScopedActorException(ScopedActorError.down);

            // TODO: this loop is stupid... should use a conditional variable
            // instead but that requires changing the mailbox. later
            do {
                rs.rs.self.process(Clock.currTime);
                // force the actor to be alive even though there are no behaviors.
                rs.rs.self.state_ = ActorState.waiting;

                if (self.data.get.errSt == ScopedActorError.none) {
                    dynIntervalSleep;
                } else {
                    throw new ScopedActorException(self.data.get.errSt);
                }

            }
            while (self.data.get.self.waitingForReply);
        }
    }
}

ScopedActor scopedActor(string file = __FILE__, uint line = __LINE__)() @safe {
    import std.format : format;

    return ScopedActor(makeAddress2, format!"ScopedActor.%s:%s"(file, line));
}

@(
        "scoped actor shall throw an exception if the actor that is sent a request terminates or is closed")
unittest {
    import my.actor.system;

    auto sys = makeSystem;

    auto a0 = sys.spawn((Actor* self) {
        return impl(self, (ref CSelf!() ctx, int x) {
            Thread.sleep(50.dur!"msecs");
            return 42;
        }, capture(self), (ref CSelf!() ctx, double x) {}, capture(self),
            (ref CSelf!() ctx, string x) { ctx.self.shutdown; return 42; }, capture(self));
    });

    {
        auto self = scopedActor;
        bool excThrown;
        auto stopAt = Clock.currTime + 3.dur!"seconds";
        while (!excThrown && Clock.currTime < stopAt) {
            try {
                self.request(a0, delay(1.dur!"nsecs")).send(42).then((int x) {});
            } catch (ScopedActorException e) {
                excThrown = e.error == ScopedActorError.timeout;
            } catch (Exception e) {
                logger.info(e.msg);
            }
        }
        assert(excThrown, "timeout did not trigger as expected");
    }

    {
        auto self = scopedActor;
        bool excThrown;
        auto stopAt = Clock.currTime + 3.dur!"seconds";
        while (!excThrown && Clock.currTime < stopAt) {
            try {
                self.request(a0, delay(1.dur!"seconds")).send("hello").then((int x) {
                });
            } catch (ScopedActorException e) {
                excThrown = e.error == ScopedActorError.down;
            } catch (Exception e) {
                logger.info(e.msg);
            }
        }
        assert(excThrown, "detecting terminated actor did not trigger as expected");
    }
}
