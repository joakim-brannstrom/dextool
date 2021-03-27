/**
 * [Source](https://raw.githubusercontent.com/schveiguy/iopipe/makesafe/source/iopipe/refc.d).
 *
 * Reference counting using the GC.
 *
 * The RefCounted struct simply stores the item in a GC block, and also adds a
 * root to that block. Once all known references to the block are removed
 * (tracked by a reference count in the block), then the block is removed, and
 * the destructor run. Since it's a root, it can run the full destructor of the
 * data underneath, without worrying about GC data being collected underneath
 * it.
 *
 * This depends on the block not being involved in a cycle, which should be
 * fine for iopipes.
 *
 * Note that atomics are used for the reference count because the GC can
 * destroy things in other threads.
 */
module my.gc.refc;

import core.atomic : atomicOp, atomicLoad, atomicStore, cas;
import core.memory : GC;
import std.algorithm : move, swap;

/**
 * The "use count" is the number of shared_ptr instances pointing to the
 * object.
 * The "weak count" is the number of weak_ptr instances pointing to the object,
 * plus one if the "use count" is still > 0.
 */
private struct ControlBlock(T) {
    T item;
    /// Number of RefCounted instances.
    shared int useCnt = 1;
    /// Number of weak references. +1 if useCnt isn't zero.
    shared int weakCnt = 1;

    this(ref T item_) {
        item = move(item_);
    }

    this(Args...)(auto ref Args args) {
        item = T(args);
    }
}

private void incrUseCnt(T)(ref T cb) nothrow {
    cb.useCnt.atomicOp!"+="(1);
}

private void releaseUseCnt(T)(ref T cb) {
    assert(cb.useCnt >= 0, "Invalid count detected");

    if (cb.useCnt.atomicOp!"-="(1) == 0) {
        destroy(cb.item);
        releaseWeakCnt(cb);
    }
}

private void incrWeakCnt(T)(ref T cb) nothrow {
    cb.weakCnt.atomicOp!"+="(1);
}

private void releaseWeakCnt(T)(ref T cb) @trusted {
    assert(cb.weakCnt >= 0, "Invalid count detected");

    if (cb.weakCnt.atomicOp!"-="(1) == 0) {
        GC.removeRoot(cb);
    }
}

/** `RefCounted` is a smart pointer that retains shared ownership of an object
 * through a pointer. Several `RefCounted` objects may own the same object. The
 * object is destroyed and its memory deallocated when either of the following
 * happens:
 *
 *  * the last remaining `RefCounted` owning the object is destroyed;
 *  * the last remaining `RefCounted` owning the object is assigned another
 *    pointer via `opAssign` or `release()`.
 *
 * The object is destroyed using the objects destructor.
 *
 * A `RefCounted` may also own no objects, in which case it is called empty and
 * `isNull()` returns true.
 *
 * All member functions can be called by multiple threads on different
 * instances of shared_ptr without additional synchronization even if these
 * instances are copies and share ownership of the same object. If multiple
 * threads of execution access the same shared_ptr without synchronization and
 * any of those accesses uses a non-const member function of shared_ptr then a
 * data race will occur; the shared_ptr overloads of atomic functions can be
 * used to prevent the data race.
 */
struct RefCounted(T) {
    alias Impl = ControlBlock!T;
    private Impl* impl;
    private T* item;

    this(Impl* impl) {
        this.impl = impl;
        setLocalItem;
    }

    this(Args...)(auto ref Args args) {
        import std.conv : emplace;

        impl = alloc();
        () @trusted { emplace(impl, args); GC.addRoot(impl); }();
        setLocalItem;
    }

    this(this) {
        if (impl) {
            incrUseCnt(impl);
        }
    }

    ~this() {
        if (impl) {
            releaseUseCnt(impl);
        }
    }

    /// Set impl to an allocated block of data. It is uninitialized.
    private static Impl* alloc() @trusted {
        // need to use untyped memory, so we don't get a dtor call by the GC.
        import std.traits : hasIndirections;

        static if (hasIndirections!T)
            auto rawMem = new void[Impl.sizeof];
        else
            auto rawMem = new ubyte[Impl.sizeof];
        return (() @trusted => cast(Impl*) rawMem.ptr)();
    }

    private void setLocalItem() @trusted {
        if (impl)
            item = &impl.item;
    }

    ref inout(T) get() inout {
        assert(impl, "Invalid refcounted access");
        return *item;
    }

    void opAssign(RefCounted other) {
        swap(impl, other.impl);
        setLocalItem;
    }

    void opAssign(T other) {
        import std.conv : emplace;

        if (empty) {
            impl = alloc;
            () @trusted { emplace(impl, other); GC.addRoot(impl); }();
        } else {
            move(other, impl.item);
        }
        setLocalItem;
    }

    /// Release the reference.
    void release() {
        if (impl) {
            releaseUseCnt(impl);
            impl = null;
        }
    }

    /// The number of references.
    int refCount() @safe pure nothrow const @nogc {
        if (impl) {
            return atomicLoad(impl.useCnt);
        }
        return 0;
    }

    bool empty() @safe pure nothrow const @nogc {
        return impl is null;
    }

    WeakRef!T weakRef() {
        return WeakRef!T(this);
    }

    alias get this;
}

RefCounted!T refCounted(T)(auto ref T item) {
    return RefCounted!T(item);
}

@safe unittest {
    size_t dtorcalled = 0;
    struct S {
        int x;
        @safe ~this() {
            if (x)
                dtorcalled++;
        }

        @disable this(this);
    }

    {
        auto destroyme = S(1).refCounted;
        auto dm2 = destroyme;
        auto dm3 = destroyme;
        assert(destroyme.refCount == 3);
        assert(dm2.refCount == 3);
        assert(dm3.refCount == 3);
    }

    assert(dtorcalled == 1);
}

/** `WeakRef` is a smart pointer that holds a non-owning ("weak") reference to
 * an object that is managed by `RefCounted`. It must be converted to a
 * `RefCounted` via `asRefCounted()` in order to access the referenced object.
 *
 * `WeakRef` models temporary ownership: when an object needs to be accessed
 * only if it exists, and it may be deleted at any time by someone else,
 * `WeakRef` is used to track the object, and it is converted to `RefCounted`
 * to assume temporary ownership. If the original `RefCounted` is destroyed at
 * this time, the object's lifetime is extended until the temporary
 * `RefCounted` is destroyed as well.
 *
 * Another use for `WeakRef` is to break reference cycles formed by objects
 * managed by `RefCounted`. if such cycle is orphaned (i.e. there are no
 * outside shared pointers into the cycle), the `RefCounted` reference counts
 * cannot reach zero and the memory is leaked. To prevent this, one of the
 * pointers in the cycle can be made weak.
 */
struct WeakRef(T) {
    alias Impl = ControlBlock!T;
    private Impl* impl;
    private T* item;

    this(RefCounted!T r) {
        incrWeakCnt(r.impl);
        scope (failure) {
            releaseWeakCnt(r.impl);
        }
        impl = r.impl;
    }

    this(ref RefCounted!T r) @safe nothrow {
        incrWeakCnt(r.impl);
        impl = r.impl;
        setLocalItem;
    }

    this(this) {
        if (impl) {
            incrWeakCnt(impl);
        }
    }

    ~this() @safe {
        if (impl) {
            releaseWeakCnt(impl);
        }
    }

    private void setLocalItem() @trusted {
        if (impl)
            item = &impl.item;
    }

    void opAssign(WeakRef other) @safe nothrow {
        swap(impl, other.impl);
        setLocalItem;
    }

    RefCounted!T asRefCounted() nothrow {
        if (impl is null) {
            return RefCounted!T.init;
        }

        auto useCnt = atomicLoad(impl.useCnt);
        if (useCnt == 0)
            return RefCounted!T.init;

        cas(&impl.useCnt, useCnt, useCnt + 1);
        return RefCounted!T(impl);
    }

    /// Release the reference.
    void release() @safe nothrow @nogc {
        if (impl) {
            releaseWeakCnt(impl);
            impl = null;
        }
    }

    /** If the `WeakRef` reference a `RefCounted`.
     *
     * This only mean that `asRefCounted` can be used to try and get the data.
     * No guarantee that it will succeed.
     */
    bool empty() @safe pure nothrow const @nogc {
        return impl is null;
    }
}

/// shall only call the destructor one time.
@safe unittest {
    size_t dtorcalled = 0;
    struct S {
        int x;
        @safe ~this() {
            if (x)
                dtorcalled++;
        }

        @disable this(this);
    }

    {
        auto rc1 = S(1).refCounted;
        assert(rc1.refCount == 1);
        assert(rc1.impl.weakCnt == 1);
        auto rc2 = rc1;
        assert(rc2.refCount == 2);
        assert(rc2.impl.weakCnt == 1);

        auto wrc1 = rc1.weakRef;
        assert(wrc1.impl.useCnt == 2);
        assert(wrc1.impl.weakCnt == 2);
    }

    assert(dtorcalled == 1);
}

/// shall destroy the object even though there are cycles because they are WeakRef.
@safe unittest {
    size_t dtorcalled = 0;
    struct S {
        int x;
        WeakRef!(typeof(this)) other;

        @safe ~this() {
            if (x)
                dtorcalled++;
        }

        @disable this(this);
    }

    {
        auto rc1 = S(1).refCounted;
        auto rc2 = S(2).refCounted;

        rc1.other = rc2.weakRef;
        rc2.other = rc1.weakRef;

        assert(rc1.impl.useCnt == 1);
        assert(rc1.impl.weakCnt == 2);
        assert(rc2.impl.useCnt == 1);
        assert(rc2.impl.weakCnt == 2);
    }

    assert(dtorcalled == 2);
}
