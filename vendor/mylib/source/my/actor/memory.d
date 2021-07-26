/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Allocators used by system.
*/
module my.actor.memory;

import core.sync.mutex : Mutex;

import my.actor.actor : Actor;
import my.actor.mailbox : Address, makeAddress;

import std.stdio;

/** Assuming that the `System` instance ensure that only actors creating with
 * the allocator are deallocated. If everything goes OK it means that an actor
 * reach the state `shutdown` and is then disposed of by `System`.
 *
 */
struct ActorAlloc {
    import core.memory : GC;
    import std.experimental.allocator.mallocator : Mallocator;

    // lazy for now and just use the global allocator.
    alias allocator_ = Mallocator.instance;

    enum Sz = Actor.sizeof;

    Actor* make(Address* addr) @trusted {
        import std.experimental.allocator : make;

        auto rval = make!Actor(allocator_, addr);
        GC.addRange(rval, Sz);

        return rval;
    }

    void dispose(Actor* a) @trusted {
        static import my.alloc.dispose_;

        my.alloc.dispose_.dispose(allocator_, a);

        GC.removeRange(a);
    }
}

@("shall allocate and dellacate an actor")
unittest {
    import core.memory : GC;

    ActorAlloc aa;
    foreach (_; 0 .. 10) {
        auto a = aa.make(makeAddress);
        aa.dispose(a);
        GC.collect;
    }
}
