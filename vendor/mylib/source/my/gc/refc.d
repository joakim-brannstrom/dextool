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
import std.traits : isInstanceOf;

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

private void releaseUseCnt(T)(ref T cb)
in (cb.useCnt >= 0, "Invalid count detected") {
    if (cb.useCnt.atomicOp!"-="(1) == 0) {
        if (!GC.inFinalizer)
            destroy(cb.item);
        releaseWeakCnt(cb);
    }
}

private void incrWeakCnt(T)(ref T cb) nothrow {
    cb.weakCnt.atomicOp!"+="(1);
}

private void releaseWeakCnt(T)(ref T cb) @trusted
in (cb.weakCnt >= 0, "Invalid count detected") {
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
    import std.conv : emplace;

    alias Impl = ControlBlock!T;
    private Impl* impl;

    this(Impl* impl) {
        this.impl = impl;
    }

    this(Args...)(auto ref Args args) {
        impl = alloc();
        () @trusted {
            scope (failure)
                GC.removeRoot(impl);
            emplace(impl, args);
        }();
    }

    this(this) {
        if (impl)
            incrUseCnt(impl);
    }

    ~this() {
        if (impl)
            releaseUseCnt(impl);
        impl = null;
    }

    alias get this;

    /// Set impl to an allocated block of data. It is uninitialized.
    private static Impl* alloc() @trusted {
        // need to use untyped memory, so we don't get a dtor call by the GC.
        import std.traits : hasIndirections;

        static if (hasIndirections!T) {
            auto rawMem = new void[Impl.sizeof];
            GC.addRoot(rawMem.ptr);
        } else {
            auto rawMem = new ubyte[Impl.sizeof];
        }

        auto rval = cast(Impl*) rawMem.ptr;
        rval.useCnt = 1;
        rval.weakCnt = 1;
        return rval;
    }

    private inout(T*) item() inout @trusted
    in (impl !is null, "not initialized") {
        return cast(inout(T*)) impl;
    }

    /// Returns: pointer to the item or null.
    inout(T*) ptr() inout return {
        return item;
    }

    ref inout(T) get() inout pure
    in (item !is null, "Invalid refcounted access") {
        return *item;
    }

    // creates forwarding problem but is convenient.
    //alias get this;

    size_t toHash() @safe pure nothrow const @nogc scope {
        return cast(size_t) impl;
    }

    void opAssign(RefCounted other) {
        swap(impl, other.impl);
    }

    void opAssign(T other) {
        if (empty)
            impl = alloc;
        move(other, impl.item);
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

    T opCast(T : bool)() @safe pure nothrow const @nogc {
        return !empty;
    }

    WeakRef!T weakRef() {
        return WeakRef!T(impl);
    }
}

RefCounted!T refCounted(T)(auto ref T item) {
    return RefCounted!T(item);
}

@("shall call the destructor when the last ref is destroyed")
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

    private this(Impl* impl) {
        if (impl) {
            this.impl = impl;
            incrWeakCnt(this.impl);
        }
    }

    this(this) {
        if (impl)
            incrWeakCnt(impl);
    }

    ~this() @safe {
        if (impl)
            releaseWeakCnt(impl);
        impl = null;
    }

    size_t toHash() @safe pure nothrow const @nogc scope {
        return cast(size_t) impl;
    }

    void opAssign(WeakRef other) @safe nothrow {
        swap(impl, other.impl);
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

    T opCast(T : bool)() @safe pure nothrow const @nogc {
        return !empty;
    }
}

RefCounted!(T) asRefCounted(T)(ref WeakRef!T weak) nothrow {
    if (weak.impl is null) {
        return typeof(return).init;
    }

    auto useCnt = atomicLoad(weak.impl.useCnt);
    if (useCnt == 0)
        return typeof(return).init;

    // useCnt can change but it will never go to zero because *this*
    // RefCounted keep it >0.
    while (!cas(&weak.impl.useCnt, useCnt, useCnt + 1)) {
        useCnt = atomicLoad(weak.impl.useCnt);
    }
    return typeof(return)(weak.impl);
}

@("shall only call the destructor one time")
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

@("shall destroy the object even though there are cycles because they are WeakRef")
@safe unittest {
    size_t dtorcalled = 0;
    struct S {
        int x;
        WeakRef!S other;

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

@("shall ref count an object stored in a Variant")
@system unittest {
    import std.variant : Variant;
    import std.typecons : tuple, Tuple;

    static struct S {
        int x;
    }

    auto rc = S(42).refCounted;

    {
        Variant obj;

        obj = rc;
        assert(rc.refCount == 2, "count incr when stored");

        obj = 42;
        assert(rc.refCount == 1, "count decrease when obj is destroyed");

        {
            obj = rc.weakRef;
            assert(rc.refCount == 1, "the use count did not change");
            assert(rc.impl.weakCnt == 2, "weak count incr");
        }

        { // lets get the object back via the weak ref
            auto tmpRef = obj.get!(WeakRef!S);
            assert(rc.impl.weakCnt == 3);
            auto tmpRc = tmpRef.asRefCounted;
            assert(tmpRc.get.x == 42);
        }
        assert(rc.impl.weakCnt == 2);
    }

    assert(rc.refCount == 1,
            "when last ref of obj disappears the dtor is called. only one ref left");
    assert(rc.impl.weakCnt == 1);
}

@("shall ref count an object stored in nested Variant")
@system unittest {
    import std.variant : Variant;
    import std.typecons : tuple, Tuple;

    static struct S {
        int x;
    }

    auto rc = S(42).refCounted;

    {
        auto obj = Variant(rc.weakRef);
        assert(rc.refCount == 1, "the use count did not change");
        assert(rc.impl.weakCnt == 2, "weak count incr");

        { // nested Variants call ctor/dtor as expected
            auto obj2 = Variant(tuple(42, obj));
            assert(rc.refCount == 1);
            assert(rc.impl.weakCnt == 3);
        }
    }

    assert(rc.refCount == 1,
            "when last ref of obj disappears the dtor is called. only one ref left");
}

/**
Borrows the payload of $(LREF RefCounted) for use in `fun`. Inferred as `@safe`
if `fun` is `@safe` and does not escape a reference to the payload.
The reference count will be incremented for the duration of the operation,
so destroying the last reference will not leave dangling references in
`fun`.

Params:
  fun = A callable accepting the payload either by value or by reference.
  refCount = The counted reference to the payload.
Returns:
  The return value of `fun`, if any. `ref` in the return value will be
  forwarded.
Issues:
  For yet unknown reason, code that uses this function with UFCS syntax
  will not be inferred as `@safe`. It will still compile if the code is
  explicitly marked `@safe` and nothing in `fun` prevents that.
*/
template borrow(alias fun) {
    import std.functional : unaryFun;

    auto ref borrow(RC)(RC refCount)
            if (isInstanceOf!(RefCounted, RC) && is(typeof(unaryFun!fun(refCount.get)))) {
        assert(!refCount.empty);

        // If `fun` escapes a reference to the payload, it will be inferred
        // as unsafe due to the scope storage class here.
        scope plPtr = refCount.ptr;
        return unaryFun!fun(*plPtr);

        // We destroy our copy of the reference here, automatically destroying
        // the payload if `fun` destroyed the last reference outside.
    }
}

/// This example can be marked `@safe` with `-preview=dip1000`.
@safe nothrow unittest {
    auto rcInt = refCounted(5);
    assert(rcInt.borrow!(theInt => theInt) == 5);
    auto sameInt = rcInt;
    assert(sameInt.borrow!"a" == 5);

    // using `ref` in the function
    auto arr = [0, 1, 2, 3, 4, 5, 6];
    sameInt.borrow!(ref(x) => arr[x]) = 10;
    assert(arr == [0, 1, 2, 3, 4, 10, 6]);

    // modifying the payload via an alias
    sameInt.borrow!"a*=2";
    assert(rcInt.borrow!"a" == 10);
}
