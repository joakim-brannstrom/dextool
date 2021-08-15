/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module my.actor.typed;

import std.datetime : SysTime, Clock;
import std.meta : AliasSeq, staticMap;
import std.traits : Unqual, isFunction, isDelegate, Parameters, ReturnType, isFunctionPointer;
import std.typecons : Tuple, tuple;

import my.actor.actor : Actor, ErrorHandler, DownHandler, ExitHandler,
    ExceptionHandler, DefaultHandler;
import my.actor.common : makeSignature;
import my.actor.mailbox : StrongAddress, WeakAddress, Address, Msg, MsgType, makeAddress2;
import my.actor.msg;
import my.actor.system : System;

enum isTypedActor(T) = is(T : TypedActor!U, U);
enum isTypedActorImpl(T) = is(T : TypedActorImpl!U, U);
enum isTypedAddress(T) = is(T : TypedAddress!U, U);

/// Signature for a typed actor.
struct TypedActor(AllowedMsg...) {
    alias AllowedMessages = AliasSeq!AllowedMsg;
    alias Address = TypedAddress!AllowedMessages;
    alias Impl = TypedActorImpl!AllowedMessages;
}

private template toTypedMsgs(AllowedMsg...) {
    static if (AllowedMsg.length == 1)
        alias toTypedMsgs = ToTypedMsg!(AllowedMsg[0], false);
    else
        alias toTypedMsgs = AliasSeq!(ToTypedMsg!(AllowedMsg[0], false),
                toTypedMsgs!(AllowedMsg[1 .. $]));
}

/// Construct the type representing a typed actor.
template typedActor(AllowedMsg...) {
    alias typedActor = TypedActor!(toTypedMsgs!AllowedMsg);
}

/// Actor implementing the type actors requirements.
struct TypedActorImpl(AllowedMsg...) {
    alias AllowedMessages = AliasSeq!AllowedMsg;
    alias Address = TypedAddress!AllowedMessages;

    package Actor* actor;

    void shutdown() @safe nothrow {
        actor.shutdown;
    }

    void forceShutdown() @safe nothrow {
        actor.forceShutdown;
    }

    /// Set name name of the actor.
    void name(string n) @safe pure nothrow @nogc {
        actor.name = n;
    }

    void errorHandler(ErrorHandler v) @safe pure nothrow @nogc {
        actor.errorHandler = v;
    }

    void downHandler(DownHandler v) @safe pure nothrow @nogc {
        actor.downHandler = v;
    }

    void exitHandler(ExitHandler v) @safe pure nothrow @nogc {
        actor.exitHandler = v;
    }

    void exceptionHandler(ExceptionHandler v) @safe pure nothrow @nogc {
        actor.exceptionHandler = v;
    }

    void defaultHandler(DefaultHandler v) @safe pure nothrow @nogc {
        actor.defaultHandler = v;
    }

    TypedAddress!AllowedMessages address() @safe {
        return TypedAddress!AllowedMessages(actor.address);
    }

    ref System homeSystem() @safe pure nothrow @nogc {
        return actor.homeSystem;
    }
}

/// Type safe address used to verify messages before they are sent.
struct TypedAddress(AllowedMsg...) {
    alias AllowedMessages = AliasSeq!AllowedMsg;
    package {
        WeakAddress address;

        this(StrongAddress a) {
            address = a.weakRef;
        }

        this(WeakAddress a) {
            address = a;
        }

        package ref inout(WeakAddress) opCall() inout {
            return address;
        }
    }
}

auto extend(TActor, AllowedMsg...)() if (isTypedActor!TActor) {
    alias dummy = typedActor!AllowedMsg;
    return TypedActor!(AliasSeq!(TActor.AllowedMessages, dummy.AllowedMessages));
}

package template ParamsToTuple(T...)
        if (T.length > 1 || T.length == 1 && !is(T[0] == void)) {
    static if (T.length == 1)
        alias ParamsToTuple = Tuple!(T[0]);
    else
        alias ParamsToTuple = Tuple!(staticMap!(Unqual, T));
}

package template ReturnToTupleOrVoid(T) {
    static if (is(T == void))
        alias ReturnToTupleOrVoid = void;
    else {
        static if (is(T == Tuple!U, U))
            alias ReturnToTupleOrVoid = T;
        else
            alias ReturnToTupleOrVoid = Tuple!T;
    }
}

package template ToTypedMsg(T, bool HasContext)
        if ((isFunction!T || isDelegate!T || isFunctionPointer!T) && Parameters!T.length != 0) {
    import my.actor.actor : Promise, RequestResult;

    static if (HasContext)
        alias RawParams = Parameters!T[1 .. $];
    else
        alias RawParams = Parameters!T;
    static if (is(ReturnType!T == Promise!PT, PT))
        alias RawReply = PT;
    else static if (is(ReturnType!T == RequestResult!RT, RT)) {
        alias RawReply = RT;
    } else
        alias RawReply = ReturnType!T;

    alias Params = ParamsToTuple!RawParams;
    alias Reply = ReturnToTupleOrVoid!RawReply;

    alias ToTypedMsg = TypedMsg!(Params, Reply);
}

package struct TypedMsg(P, R) {
    alias Params = P;
    alias Reply = R;
}

package bool IsEqual(TypedMsg1, TypedMsg2)() {
    return is(TypedMsg1.Params == TypedMsg2.Params) && is(TypedMsg1.Reply == TypedMsg2.Reply);
}

/** Check that `Behavior` implement the actor interface `TActor` at compile
 * time. If successfull an actor is built that implement `TActor`.
 */
auto impl(TActor, Behavior...)(TActor actor, Behavior behaviors)
        if (isTypedActorImpl!TActor && typeCheckImpl!(TActor, Behavior)) {
    import my.actor.actor : build;
    import my.actor.msg : isCapture, Capture;

    auto bactor = build(actor.actor);
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
    return TypedActorImpl!(TActor.AllowedMessages)(bactor.finalize);
}

private string prettify(T)() if (is(T : TypedMsg!(U, V), U, V)) {
    import std.traits : fullyQualifiedName;

    string s;
    s ~= "(";
    static foreach (P; T.Params.expand)
        s ~= fullyQualifiedName!(typeof(P)) ~ ",";
    s ~= ") -> (";
    static if (is(T.Reply == void)) {
        s ~= "void";
    } else {
        static foreach (P; T.Reply.expand)
            s ~= fullyQualifiedName!(typeof(P)) ~ ",";
    }
    s ~= ")";
    return s;
}

private bool typeCheckImpl(TActor, Behavior...)() {
    // check that the specification is implemented and no duplications.
    // will allow an actor have more behaviors than the specification allow.
    foreach (T; TActor.AllowedMessages) {
        bool reqRepOk;
        // only one parameter match is allowed or else req/rep is overwritten
        // when constructing the actor.
        bool paramsMatch;
        static foreach (const i; 0 .. Behavior.length) {
            {
                alias bh = Behavior[i];
                // look ahead one step to determine if it is a capture. If so then the parameters are reduced
                static if (i + 1 < Behavior.length && isCapture!(Behavior[i + 1]))
                    enum HasContext = true;
                else
                    enum HasContext = false;

                static if (!isCapture!bh) {
                    alias Msg = ToTypedMsg!(bh, HasContext);

                    static if (is(T.Params == Msg.Params)) {
                        if (paramsMatch) {
                            assert(false, "duplicate implementation parameters of " ~ prettify!T);
                        }
                        paramsMatch = true;
                    }

                    static if (IsEqual!(T, Msg)) {
                        if (reqRepOk) {
                            assert(false, "duplicate implementation of " ~ prettify!T);
                        }
                        reqRepOk = true;
                    }
                }
            }
        }

        if (!reqRepOk) {
            assert(false, "missing implementation of " ~ prettify!T);
        }
    }
    return true;
}

/// Check if `TAddress` can receive the message.
package bool typeCheckMsg(TAllowed, R, Params...)() {
    alias AllowedTypes = TAllowed.AllowedMessages;
    alias MsgT = TypedMsg!(ParamsToTuple!Params, ReturnToTupleOrVoid!R);

    //pragma(msg, TAllowed);
    //pragma(msg, R);
    //pragma(msg, Params);
    //pragma(msg, MsgT);

    bool rval;
    foreach (T; AllowedTypes) {
        static if (IsEqual!(T, MsgT)) {
            rval = true;
            break;
        }
    }
    assert(rval, "actor cannot receive message " ~ prettify!MsgT);

    return rval;
}

@(
        "shall construct a typed actor with a behavior for msg->reply and process two messages with response")
unittest {
    alias MyActor = typedActor!(int delegate(int), Tuple!(string, int) delegate(int, double));

    int called;
    static int fn1(ref Capture!(int*, "called") c, int x) {
        return (*c.called)++;
    }

    auto aa1 = Actor(makeAddress2);
    auto actor = impl(MyActor.Impl(&aa1), &fn1, capture(&called),
            (ref Capture!(int*, "called") ctx, int, double) {
        (*ctx.called)++;
        return tuple("hej", 42);
    }, capture(&called));

    actor.request(actor.address, infTimeout).send(42).capture(&called)
        .then((ref Capture!(int*, "called") ctx, int x) {
            return (*ctx.called)++;
        });
    actor.request(actor.address, infTimeout).send(42, 43.0).capture(&called)
        .then((ref Capture!(int*, "called") ctx, string a, int b) {
            if (a == "hej" && b == 42)
                (*ctx.called)++;
        });

    // check that the code in __traits is correct
    static assert(__traits(compiles, {
            actor.request(actor.address, infTimeout).send(42).then((int x) {});
        }));
    // check that the type check works, rejecting the message because the actor
    // do not accept it or the continuation (.then) has the wrong parameters.
    //static assert(!__traits(compiles, {
    //        actor.request(actor.address, infTimeout).send(43.0).then((int x) {});
    //    }));
    //static assert(!__traits(compiles, {
    //        actor.request(actor.address, infTimeout).send(42).then((string x) {});
    //    }));

    foreach (_; 0 .. 3)
        actor.actor.process(Clock.currTime);

    assert(called == 4);
}

@("shall construct a typed actor and process two messages")
unittest {
    alias MyActor = typedActor!(void delegate(int), void delegate(int, double));

    int called;
    static void fn1(ref Capture!(int*, "called") c, int x) {
        (*c.called)++;
    }

    auto aa1 = Actor(makeAddress2);
    auto actor = impl(MyActor.Impl(&aa1), &fn1, capture(&called),
            (ref Capture!(int*, "called") c, int, double) { (*c.called)++; }, capture(&called));

    send(actor.address, 42);
    send(actor, 42, 43.0);

    // check that the code in __traits is correct
    static assert(__traits(compiles, { send(actor.address, 42); }));
    // check that the type check works, rejecting the message because the actor do not accept it.
    static assert(!__traits(compiles, { send(actor.address, 43.0); }));

    actor.actor.process(Clock.currTime);
    actor.actor.process(Clock.currTime);

    assert(called == 2);
}

@("shall type check msg->reply")
unittest {
    {
        alias Msg = ToTypedMsg!(string delegate(int), false);
        static assert(is(Msg == TypedMsg!(Tuple!int, Tuple!string)));
    }
    {
        alias Msg = ToTypedMsg!(string delegate(int, int), false);
        static assert(is(Msg == TypedMsg!(Tuple!(int, int), Tuple!string)));
    }
    {
        alias Msg = ToTypedMsg!(Tuple!(int, string) delegate(int, int), false);
        static assert(is(Msg == TypedMsg!(Tuple!(int, int), Tuple!(int, string))));
    }
    {
        alias Msg = ToTypedMsg!(void delegate(int, int), false);
        static assert(is(Msg == TypedMsg!(Tuple!(int, int), void)));
    }

    static assert(IsEqual!(ToTypedMsg!(string delegate(int), false),
            ToTypedMsg!(string delegate(int), false)));
}

package StrongAddress underlyingAddress(T)(T address)
        if (is(T == Actor*) || is(T == StrongAddress) || is(T == WeakAddress)
            || isTypedAddress!T || isTypedActorImpl!T) {
    static StrongAddress toStrong(WeakAddress wa) {
        if (auto a = wa.lock)
            return a;
        return StrongAddress.init;
    }

    static if (isTypedAddress!T) {
        return toStrong(address.address);
    } else static if (isTypedActorImpl!T)
        return toStrong(address.address.address);
    else static if (is(T == Actor*))
        return address.addressRef;
    else static if (is(T == WeakAddress)) {
        return toStrong(address);
    } else
        return address;
}

package WeakAddress underlyingWeakAddress(T)(T x)
        if (is(T == Actor*) || is(T == StrongAddress) || is(T == WeakAddress)
            || isTypedAddress!T || isTypedActorImpl!T) {
    static if (isTypedAddress!T) {
        return x.address;
    } else static if (isTypedActorImpl!T)
        return x.address.address;
    else static if (is(T == Actor*))
        return x.address;
    else static if (is(T == StrongAddress)) {
        return x.weakRef;
    } else
        return x;
}

package auto underlyingTypedAddress(T)(T address)
        if (isTypedAddress!T || isTypedActorImpl!T) {
    static if (isTypedAddress!T)
        return address;
    else
        return address.address;
}

package Actor* underlyingActor(T)(T actor) if (is(T == Actor*) || isTypedActorImpl!T) {
    static if (isTypedActorImpl!T)
        return actor.actor;
    else
        return actor;
}
