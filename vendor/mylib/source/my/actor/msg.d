/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module my.actor.msg;

import logger = std.logger;
import std.meta : staticMap, AliasSeq;
import std.traits : Unqual, Parameters, isFunction, isFunctionPointer;
import std.typecons : Tuple, tuple;
import std.variant : Variant;

public import std.datetime : SysTime, Duration, dur;

import my.actor.mailbox;
import my.actor.common : ExitReason, makeSignature, SystemError;
import my.actor.actor : Actor, makeReply2, makePromise, ErrorHandler, Promise, RequestResult;
import my.actor.system_msg;
import my.actor.typed : isTypedAddress, isTypedActor, isTypedActorImpl,
    typeCheckMsg, ParamsToTuple, ReturnToTupleOrVoid,
    underlyingActor, underlyingAddress, underlyingTypedAddress, underlyingWeakAddress;

SysTime infTimeout() @safe pure nothrow {
    return SysTime.max;
}

SysTime timeout(Duration d) @safe nothrow {
    import std.datetime : Clock;

    return Clock.currTime + d;
}

/// Code looks better if it says delay when using delayedSend.
alias delay = timeout;

enum isActor(T) = is(T == Actor*) || isTypedActor!T || isTypedActorImpl!T;
enum isAddress(T) = is(T == WeakAddress) || is(T == StrongAddress) || isTypedAddress!T;
enum isDynamicAddress(T) = is(T == WeakAddress) || is(T == StrongAddress);

/** Link the lifetime of `self` to the actor using `sendTo`.
 *
 * An `ExitMsg` is sent to `self` if `sendTo` is terminated and vice versa.
 *
 * `ExitMsg` triggers `exitHandler`.
 */
void linkTo(AddressT0, AddressT1)(AddressT0 self, AddressT1 sendTo) @safe
        if ((isActor!AddressT0 || isAddress!AddressT0) && (isActor!AddressT1
            || isAddress!AddressT1)) {
    import my.actor.mailbox : LinkRequest;

    auto self_ = underlyingAddress(self);
    auto addr = underlyingAddress(sendTo);

    if (self_.empty || addr.empty)
        return;

    sendSystemMsg(self_, LinkRequest(addr.weakRef));
    sendSystemMsg(addr, LinkRequest(self_.weakRef));
}

/// Remove the link between `self` and the actor using `sendTo`.
void unlinkTo(AddressT0, AddressT1)(AddressT0 self, AddressT1 sendTo) @safe
        if ((isActor!AddressT0 || isAddress!AddressT0) && (isActor!AddressT1
            || isAddress!AddressT1)) {
    import my.actor.mailbox : UnlinkRequest;

    auto self_ = underlyingAddress(self);
    auto addr = underlyingAddress(sendTo);

    // do NOT check if the addresses exist becuase it doesn't matter. Just
    // remove the link.

    sendSystemMsg(self_, UnlinkRequest(addr.weakRef));
    sendSystemMsg(addr, UnlinkRequest(self_.weakRef));
}

/** Actor `self` will receive a `DownMsg` when `sendTo` shutdown.
 *
 * `DownMsg` triggers `downHandler`.
 */
void monitor(AddressT0, AddressT1)(AddressT0 self, AddressT1 sendTo) @safe
        if ((isActor!AddressT0 || isAddress!AddressT0) && (isActor!AddressT1
            || isAddress!AddressT1)) {
    import my.actor.system_msg : MonitorRequest;

    if (auto self_ = underlyingAddress(self))
        sendSystemMsg(sendTo, MonitorRequest(self_.weakRef));
}

/// Remove `self` as a monitor of the actor using `sendTo`.
void demonitor(AddressT0, AddressT1)(scope AddressT0 self, scope AddressT1 sendTo) @safe
        if ((isActor!AddressT0 || isAddress!AddressT0) && (isActor!AddressT1
            || isAddress!AddressT1)) {
    import my.actor.system_msg : MonitorRequest;

    if (auto self_ = underlyingAddress(self))
        sendSystemMsg(sendTo, DemonitorRequest(self_.weakRef));
}

// Only send the message if the system message queue is empty.
package void sendSystemMsgIfEmpty(AddressT, T)(AddressT sendTo, T msg) @safe
        if (isAddress!AddressT)
in (!sendTo.empty, "cannot send to an empty address") {
    auto tmp = underlyingAddress(sendTo);
    auto addr = tmp.get;
    if (addr && addr.empty!SystemMsg)
        addr.put(SystemMsg(msg));
}

package void sendSystemMsg(AddressT, T)(scope AddressT sendTo, scope T msg) @safe
        if (isAddress!AddressT) {
    auto tmp = underlyingAddress(sendTo);
    auto addr = tmp.get;
    if (addr)
        addr.put(SystemMsg(msg));
}

/// Trigger the message in the future.
void delayedSend(AddressT, Args...)(AddressT sendTo, SysTime delayTo, auto ref Args args) @trusted
        if (is(AddressT == WeakAddress) || is(AddressT == StrongAddress) || is(AddressT == Actor*)) {
    alias UArgs = staticMap!(Unqual, Args);
    if (auto addr = underlyingAddress(sendTo).get)
        addr.put(DelayedMsg(Msg(makeSignature!UArgs,
                MsgType(MsgOneShot(Variant(Tuple!UArgs(args))))), delayTo));
}

void sendExit(AddressT)(AddressT sendTo, const ExitReason reason) @safe
        if (isAddress!AddressT) {
    import my.actor.system_msg : SystemExitMsg;

    sendSystemMsg(sendTo, SystemExitMsg(reason));
}

// TODO: add verification that args do not have interior pointers
void send(AddressT, Args...)(AddressT sendTo, auto ref Args args) @trusted
        if (isDynamicAddress!AddressT || is(AddressT == Actor*)) {
    alias UArgs = staticMap!(Unqual, Args);
    if (auto addr = underlyingAddress(sendTo).get)
        addr.put(Msg(makeSignature!UArgs, MsgType(MsgOneShot(Variant(Tuple!UArgs(args))))));
}

package struct RequestSend {
    Actor* self;
    WeakAddress requestTo;
    SysTime timeout;
    ulong replyId;

    /// Copy constructor
    this(ref return scope typeof(this) rhs) @safe pure nothrow @nogc {
        self = rhs.self;
        requestTo = rhs.requestTo;
        timeout = rhs.timeout;
        replyId = rhs.replyId;
    }
}

package struct RequestSendThen {
    RequestSend rs;
    Msg msg;

    /// Copy constructor
    this(ref return typeof(this) rhs) {
        rs = rhs.rs;
        msg = rhs.msg;
    }

    ~this() scope {
    }
}

RequestSend request(ActorT)(ActorT self, WeakAddress requestTo, SysTime timeout)
        if (is(ActorT == Actor*)) {
    return RequestSend(self, requestTo, timeout, self.nextReplyId);
}

RequestSendThen send(Args...)(RequestSend r, auto ref Args args) {
    alias UArgs = staticMap!(Unqual, Args);

    auto replyTo = r.self.addr.weakRef;

    // dfmt off
    auto msg = () @trusted {
        return Msg(
        makeSignature!UArgs,
        MsgType(MsgRequest(replyTo, r.replyId, Variant(Tuple!UArgs(args)))));
    }();
    // dfmt on

    return () @trusted { return RequestSendThen(r, msg); }();
}

private struct ThenContext(CtxT, Captures...) {
    RequestSendThen r;
    CtxT* ctx;

    void then(T)(T handler, ErrorHandler onError = null)
            if (isFunction!T || isFunctionPointer!T) {
        thenUnsafe!(T, CtxT)(r, handler, cast(void*) ctx, onError);
        ctx = null;
    }
}

// allows delegates but the context for them may be corrupted by the GC if they
// are used in another thread thus use of `thenUnsafe` must ensure it is not
// escaped.
package void thenUnsafe(T, CtxT = void)(scope RequestSendThen r, T handler,
        void* ctx, ErrorHandler onError = null) @trusted {
    auto requestTo = r.rs.requestTo.lock.get;
    if (!requestTo) {
        if (onError)
            onError(*r.rs.self, ErrorMsg(r.rs.requestTo, SystemError.requestReceiverDown));
        return;
    }

    // TODO: compiler bug? how can SysTime be inferred to being scoped?
    SysTime timeout = () @trusted { return r.rs.timeout; }();

    // first register a handler for the message.
    // this order ensure that there is always a handler that can receive the message.

    () @safe {
        auto reply = makeReply2!(T, CtxT)(handler);
        reply.ctx = ctx;
        string desc;
        debug desc = T.stringof;
        r.rs.self.register(desc, r.rs.replyId, timeout, reply, onError);
    }();

    // then send it
    requestTo.put(r.msg);
}

void then(T, CtxT = void)(scope RequestSendThen r, T handler, ErrorHandler onError = null) @trusted
        if (isFunction!T || isFunctionPointer!T) {
    thenUnsafe!(T, CtxT)(r, handler, null, onError);
}

void send(T, Args...)(T sendTo, auto ref Args args)
        if ((isTypedAddress!T || isTypedActorImpl!T) && typeCheckMsg!(T, void, Args)) {
    send(underlyingAddress(sendTo), args);
}

void delayedSend(T, Args...)(T sendTo, SysTime delayTo, auto ref Args args)
        if ((isTypedAddress!T || isTypedActorImpl!T) && typeCheckMsg!(T, void, Args)) {
    delayedSend(underlyingAddress(sendTo), delayTo, args);
}

private struct TypedRequestSend(TAddress) {
    alias TypeAddress = TAddress;
    RequestSend rs;
}

TypedRequestSend!TAddress request(TActor, TAddress)(ref TActor self, TAddress sendTo,
        SysTime timeout)
        if (isActor!TActor && (isTypedActorImpl!TAddress || isTypedAddress!TAddress)) {
    return typeof(return)(.request(underlyingActor(self), underlyingWeakAddress(sendTo), timeout));
}

private struct TypedRequestSendThen(TAddress, Params_...) {
    alias TypeAddress = TAddress;
    alias Params = Params_;
    RequestSendThen rs;

    /// Copy constructor
    this(ref return scope typeof(this) rhs) {
        rs = rhs.rs;
    }
}

auto send(TR, Args...)(scope TR tr, auto ref Args args)
        if (is(TR == TypedRequestSend!TAddress, TAddress)) {
    return TypedRequestSendThen!(TR.TypeAddress, Args)(send(tr.rs, args));
}

void then(TR, T, CtxT = void)(scope TR tr, T handler, ErrorHandler onError = null)
        if ((isFunction!T || isFunctionPointer!T) && is(TR : TypedRequestSendThen!(TAddress,
            Params), TAddress, Params...) && typeCheckMsg!(TAddress,
            ParamsToTuple!(Parameters!T), Params)) {
    then(tr.rs, handler, onError);
}

private struct TypedThenContext(TR, CtxT, Captures...) {
    import my.actor.actor : checkRefForContext, checkMatchingCtx;

    TR r;
    CtxT* ctx;

    void then(T)(T handler, ErrorHandler onError = null)
            if ((isFunction!T || isFunctionPointer!T) && typeCheckMsg!(TR.TypeAddress,
                ParamsToTuple!(Parameters!T[1 .. $]), TR.Params)) {
        // better error message for the user by checking in the body instead of
        // the constraint because the constraint gagges the static assert
        // messages.
        checkMatchingCtx!(Parameters!T[0], CtxT);
        checkRefForContext!handler;
        .thenUnsafe!(T, CtxT)(r.rs, handler, cast(void*) ctx, onError);
        ctx = null;
    }
}

alias Capture(T...) = Tuple!T;
enum isCapture(T) = is(T == Tuple!U, U);
enum isFirstParamCtx(Fn, CtxT) = is(Parameters!Fn[0] == CtxT);

/// Convenient function for capturing the actor itself when spawning.
alias CSelf(T = Actor*) = Capture!(T, "self");

auto capture(T...)(auto ref T args)
        if (!is(T[0] == RequestSendThen)
            && !is(T[0] == TypedRequestSendThen!(TAddress, Params), TAddress, Params...)) {
    static if (T.length == 1 && isCapture!(T[0])) {
        return args[0];
    } else {
        return Tuple!T(args);
    }
}

auto capture(Captures...)(RequestSendThen r, auto ref Captures captures) {
    static if (Captures.length == 1 && isCapture!(Captures[0])) {
        alias CtxT = Captures[0];
        auto ctx = new CtxT;
        *ctx = captures;
        return ThenContext!(CtxT, Captures)(r, ctx);
    } else {
        auto ctx = new Tuple!Captures(captures);
        return ThenContext!(Tuple!Captures, Captures)(r, ctx);
    }
}

auto capture(TR, Captures...)(TR r, auto ref Captures captures)
        if (is(TR : TypedRequestSendThen!(TAddress, Params), TAddress, Params...)) {
    static if (Captures.length == 1 && isCapture!(Captures[0])) {
        alias CtxT = Captures[0];
        auto ctx = new CtxT;
        *ctx = captures;
        return TypedThenContext!(TR, CtxT, Captures)(r, ctx);
    } else {
        auto ctx = new Tuple!Captures(captures);
        return TypedThenContext!(TR, Tuple!Captures, Captures)(r, ctx);
    }
}

@("a new context should copy the provided values")
unittest {
    class AClass {
        int v;
        this(int v) {
            this.v = v;
        }
    }

    class AClassWithInnerPtr {
        int* v;
        this(int v) {
            this.v = new int;
            *this.v = v;
        }
    }

    struct AStruct {
        int v;
    }

    { // common user pattern when there is uncertainty of what "capture()" do
        auto userValues = tuple!("aint", "aclass", "astruct", "ainner")(42,
                new AClass(42), AStruct(42), new AClassWithInnerPtr(42));
        auto userCtx = capture(userValues);

        assert(userCtx.aint == 42);
        assert(userCtx.aclass !is null);
        assert(userCtx.aclass.v == 42);
        assert(userCtx.astruct.v == 42);
        assert(userCtx.ainner !is null);
        assert(userCtx.ainner.v !is null);
        assert(*userCtx.ainner.v == 42);
    }
    { // how capture can be used
        auto userCtx = capture(42, new AClass(42), AStruct(42), new AClassWithInnerPtr(42));

        assert(userCtx[0] == 42);
        assert(userCtx[1].v == 42);
        assert(userCtx[2].v == 42);
        assert(userCtx[3]!is null);
        assert(userCtx[3].v !is null);
        assert(*userCtx[3].v == 42);
    }
}
