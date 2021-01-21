/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Some code is copied from Atila Neves automem.

Convenient functions to use std.experimental.allocator with classes.
*/
module my.alloc.class_;

/** Allocate a class using `allocator` and initialize with `args`
 *
 * The class will always be tracked by the GC, no option here. This is because
 * then it is easy to use this function correctly.
 */
T make(T, Allocator, Args...)(auto ref Allocator allocator, auto ref Args args)
        if (is(T == class) || is(T == interface)) {
    import core.memory : GC;
    import std.experimental.allocator : make;
    import std.functional : forward;

    auto obj = () @trusted { return make!T(allocator, forward!args); }();
    () @trusted {
        enum sz = __traits(classInstanceSize, T);
        auto repr = (cast(void*) obj)[0 .. sz];
        GC.addRange(&repr[(void*).sizeof], sz - (void*).sizeof);
    }();

    return obj;
}

void dispose(T, Allocator)(auto ref Allocator allocator_, auto ref T obj)
        if (is(T == class) || is(T == interface)) {
    enum sz = __traits(classInstanceSize, T);
    dispose(allocator_, cast(Object) obj, sz);
}

void dispose(Allocator)(auto ref Allocator allocator_, Object obj, size_t sz) {
    import core.memory : GC;
    static import my.alloc.dispose_;

    () @trusted {
        my.alloc.dispose_.dispose(allocator_, obj);
        auto repr = (cast(void*) obj)[0 .. sz];
        GC.removeRange(&repr[(void*).sizeof]);
    }();
}

/** A bundle of classes (different classes) that are destroyed and freed when
 * the bundles destructor is called.
 *
 * Intended for parts of a program where classes are continuously allocated and
 * all have the same lifetime. They are then destroyed as one. It is important
 * to not let any references to classes escape to other parts of the program
 * because that will lead to random crashes.
 *
 */
@safe struct Bundle(Allocator) {
    import std.traits : hasMember;
    import std.experimental.allocator : theAllocator;

    enum isSingleton = hasMember!(Allocator, "instance");
    enum isTheAllocator = is(Allocator == typeof(theAllocator));
    enum isGlobal = isSingleton || isTheAllocator;

    static if (isSingleton)
        alias allocator_ = Allocator.instance;
    else static if (isTheAllocator)
        alias allocator_ = theAllocator;
    else
        Allocator allocator_;

    private {
        static struct AllocObj {
            Object obj;
            // the size of an object is variable and not possible to derive
            // from obj.
            size_t sz;
        }

        AllocObj[] objects;
    }

    static if (!isGlobal) {
        /// Non-singleton allocator, must be passed in.
        this(Allocator allocator) {
            allocator_ = allocator;
        }
    }

    ~this() {
        release;
    }

    T make(T, Args...)(auto ref Args args) if (is(T == class) || is(T == interface)) {
        import std.functional : forward;

        enum sz = __traits(classInstanceSize, T);
        auto o = .make!T(allocator_, forward!args);
        objects ~= AllocObj(o, sz);
        return o;
    }

    /// Destroying and release the memory of all objects.
    void release() @trusted {
        foreach (n; objects) {
            .dispose(allocator_, n.obj, n.sz);
        }
        objects = null;
    }

    bool empty() @safe pure nothrow const @nogc {
        return objects.length == 0;
    }

    size_t length() @safe pure nothrow const @nogc {
        return objects.length;
    }
}

@("shall alloc and destroy objects")
@safe unittest {
    import std.experimental.allocator.mallocator : Mallocator;

    bool isDestroyed;

    {
        static class Foo {
            bool* x;
            this(ref bool x) @trusted {
                this.x = &x;
            }

            ~this() {
                *x = true;
            }
        }

        Bundle!Mallocator b;
        auto foo = b.make!Foo(isDestroyed);
        assert(!isDestroyed);
    }

    assert(isDestroyed);
}
