/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module my.actor.mailbox;

import logger = std.experimental.logger;
import core.sync.mutex : Mutex;
import std.datetime : SysTime;
import std.variant : Variant;

import sumtype;

import my.actor.common;
import my.gc.refc;
public import my.actor.system_msg;

struct MsgOneShot {
    Variant data;
}

struct MsgRequest {
    WeakAddress replyTo;
    ulong replyId;
    Variant data;
}

alias MsgType = SumType!(MsgOneShot, MsgRequest);

struct Msg {
    ulong signature;
    MsgType type;

    this(ref return typeof(this) a) @trusted {
        signature = a.signature;
        type = a.type;
    }

    @disable this(this);
}

alias SystemMsg = SumType!(ErrorMsg, DownMsg, ExitMsg, SystemExitMsg,
        MonitorRequest, DemonitorRequest, LinkRequest, UnlinkRequest);

struct Reply {
    ulong id;
    Variant data;

    this(ref return typeof(this) a) {
        id = a.id;
        data = a.data;
    }

    @disable this(this);
}

struct DelayedMsg {
    Msg msg;
    SysTime triggerAt;

    this(ref return DelayedMsg a) @trusted {
        msg = a.msg;
        triggerAt = a.triggerAt;
    }

    this(const ref return DelayedMsg a) inout @safe {
        assert(0, "not supported");
    }

    @disable this(this);
}

struct Address {
    private {
        // If the actor that use the address is active and processing messages.
        bool open_;
        ulong id_;
        Mutex mtx;
    }

    package {
        Queue!Msg incoming;

        Queue!SystemMsg sysMsg;

        // Delayed messages for this actor that will be triggered in the future.
        Queue!DelayedMsg delayed;

        // Incoming replies on requests.
        Queue!Reply replies;
    }

    invariant {
        assert(mtx !is null,
                "mutex must always be set or the address will fail on sporadic method calls");
    }

    private this(Mutex mtx) @safe
    in (mtx !is null) {
        this.mtx = mtx;

        // lazy way of generating an ID. a mutex is a class thus allocated on
        // the heap at a unique location. just... use the pointer as the ID.
        () @trusted { id_ = cast(ulong) cast(void*) mtx; }();
        incoming = typeof(incoming)(mtx);
        sysMsg = typeof(sysMsg)(mtx);
        delayed = typeof(delayed)(mtx);
        replies = typeof(replies)(mtx);
    }

    @disable this(this);

    void shutdown() @safe nothrow {
        try {
            synchronized (mtx) {
                open_ = false;
                incoming.teardown((ref Msg a) { a.type = MsgType.init; });
                sysMsg.teardown((ref SystemMsg a) { a = SystemMsg.init; });
                delayed.teardown((ref DelayedMsg a) { a.msg.type = MsgType.init; });
                replies.teardown((ref Reply a) { a.data = a.data.type.init; });
            }
        } catch (Exception e) {
            assert(0, "this should never happen");
        }
    }

    package bool put(T)(T msg) {
        synchronized (mtx) {
            if (!open_)
                return false;

            static if (is(T : Msg))
                return incoming.put(msg);
            else static if (is(T : SystemMsg))
                return sysMsg.put(msg);
            else static if (is(T : DelayedMsg))
                return delayed.put(msg);
            else static if (is(T : Reply))
                return replies.put(msg);
            else
                static assert(0, "msg type not supported " ~ T.stringof);
        }
    }

    package auto pop(T)() @safe {
        synchronized (mtx) {
            static if (is(T : Msg)) {
                if (!open_)
                    return incoming.PopReturnType.init;
                return incoming.pop;
            } else static if (is(T : SystemMsg)) {
                if (!open_)
                    return sysMsg.PopReturnType.init;
                return sysMsg.pop;
            } else static if (is(T : DelayedMsg)) {
                if (!open_)
                    return delayed.PopReturnType.init;
                return delayed.pop;
            } else static if (is(T : Reply)) {
                if (!open_)
                    return replies.PopReturnType.init;
                return replies.pop;
            } else {
                static assert(0, "msg type not supported " ~ T.stringof);
            }
        }
    }

    package bool empty(T)() @safe {
        synchronized (mtx) {
            if (!open_)
                return true;

            static if (is(T : Msg))
                return incoming.empty;
            else static if (is(T : SystemMsg))
                return sysMsg.empty;
            else static if (is(T : DelayedMsg))
                return delayed.empty;
            else static if (is(T : Reply))
                return replies.empty;
            else
                static assert(0, "msg type not supported " ~ T.stringof);
        }
    }

    package bool hasMessage() @safe pure nothrow const @nogc {
        try {
            synchronized (mtx) {
                return !(incoming.empty && sysMsg.empty && delayed.empty && replies.empty);
            }
        } catch (Exception e) {
        }
        return false;
    }

    package void setOpen() @safe pure nothrow @nogc {
        open_ = true;
    }

    package void setClosed() @safe pure nothrow @nogc {
        open_ = false;
    }
}

struct WeakAddress {
    private Address* addr;

    StrongAddress lock() @safe nothrow @nogc {
        return StrongAddress(addr);
    }

    T opCast(T : bool)() @safe nothrow const @nogc {
        return cast(bool) addr;
    }

    bool empty() @safe nothrow const @nogc {
        return addr is null;
    }

    void opAssign(WeakAddress rhs) @safe nothrow @nogc {
        this.addr = rhs.addr;
    }

    size_t toHash() @safe pure nothrow const @nogc scope {
        return cast(size_t) addr;
    }

    void release() @safe nothrow @nogc {
        addr = null;
    }
}

/** Messages can be sent to a strong address.
 */
struct StrongAddress {
    package {
        Address* addr;
    }

    private this(Address* addr) @safe nothrow @nogc {
        this.addr = addr;
    }

    void release() @safe nothrow @nogc {
        addr = null;
    }

    ulong id() @safe pure nothrow const @nogc {
        return cast(ulong) addr;
    }

    size_t toHash() @safe pure nothrow const @nogc scope {
        return cast(size_t) addr;
    }

    void opAssign(StrongAddress rhs) @safe nothrow @nogc {
        this.addr = rhs.addr;
    }

    T opCast(T : bool)() @safe nothrow const @nogc {
        return cast(bool) addr;
    }

    bool empty() @safe pure nothrow const @nogc {
        return addr is null;
    }

    WeakAddress weakRef() @safe nothrow {
        return WeakAddress(addr);
    }

    package Address* get() @safe pure nothrow @nogc scope return  {
        return addr;
    }
}

StrongAddress makeAddress2() @safe {
    return StrongAddress(new Address(new Mutex));
}
