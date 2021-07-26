/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module my.actor.mailbox;

import core.sync.mutex : Mutex;
import std.datetime : SysTime;
import std.variant : Variant;

import sumtype;

import my.actor.common;
public import my.actor.system_msg;

@safe:

struct Msg {
    MsgType type;
    ulong signature;
    Variant data;
}

enum MsgType {
    oneShot,
    request,
}

alias SystemMsg = SumType!(ErrorMsg, DownMsg, ExitMsg, SystemExitMsg,
        MonitorRequest, DemonitorRequest, LinkRequest, UnlinkRequest);

struct Reply {
    ulong id;
    Variant data;
}

struct DelayedMsg {
    Msg msg;
    SysTime triggerAt;
}

struct Address {
    private {
        // If the actor that use the address is active and processing messages.
        bool open_;
    }

    Queue!Msg incoming;

    Queue!SystemMsg sysMsg;

    // Delayed messages for this actor that will be triggered in the future.
    Queue!DelayedMsg delayed;

    // Incoming replies on requests.
    Queue!Reply replies;

    private this(Mutex mtx) {
        incoming = typeof(incoming)(mtx);
        sysMsg = typeof(sysMsg)(mtx);
        delayed = typeof(delayed)(mtx);
        replies = typeof(replies)(mtx);
    }

    bool hasMessage() @safe pure nothrow const @nogc {
        return !(incoming.empty && sysMsg.empty && delayed.empty && replies.empty);
    }

    bool isOpen() @safe pure nothrow const @nogc scope {
        return open_;
    }

    void setOpen() @safe pure nothrow @nogc {
        open_ = true;
    }

    void setClosed() @safe pure nothrow @nogc {
        open_ = false;
    }
}

/// Convenient type for wrapping a pointer and then used in APIs
struct AddressPtr {
    private Address* ptr_;

    this(Address* a) @safe pure nothrow @nogc {
        this.ptr_ = a;
    }

    void opAssign(const AddressPtr rhs) @trusted pure nothrow @nogc {
        // addresses can always be sent to. remove transitive const.
        this.ptr_ = cast(Address*) rhs.ptr_;
    }

    Address* ptr() @safe pure nothrow @nogc {
        return ptr_;
    }

    ref Address opCall() @safe pure nothrow @nogc scope return  {
        return *ptr_;
    }
}

Address* makeAddress() {
    return new Address(new Mutex);
}
