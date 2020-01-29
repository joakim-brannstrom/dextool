///
module cachetools.containers.orderedhashmap;

private import std.experimental.allocator.mallocator : Mallocator;
private import std.experimental.allocator.gc_allocator;
private import std.typecons;
private import std.traits;

import cachetools.internal;
import cachetools.containers.hashmap;
import cachetools.containers.lists;

///
struct OrderedHashMap(K, V, Allocator = Mallocator, bool GCRangesAllowed = true)
{

    private
    {
        alias StoredKeyType = StoredType!K;
        alias StoredValueType = StoredType!V;
        alias KeysType = CompressedList!(K, Allocator, GCRangesAllowed);
        alias HashesType = HashMap!(K, HashMapElement, Allocator, GCRangesAllowed);

        struct HashMapElement
        {
            StoredValueType value;
            KeysType.NodePointer kptr;
        }

        KeysType __keys;
        HashesType __hashes;
    }
    this(this) {
        import std.algorithm.mutation;
        KeysType keys;
        HashesType hashes;
        foreach(k; __keys) {
            auto p = keys.insertBack(k);
            if (auto vp = k in __hashes) {
                hashes.put(k, HashMapElement(vp.value, p));
            }
        }
        __keys.clear;
        __hashes.clear;
        swap(__keys,keys);
        swap(__hashes, hashes);
    }
    void opAssign(ref typeof(this) rhs) {
        if ( rhs is this ) return;
        foreach (k; rhs.__keys) {
            auto p = __keys.insertBack(k);
            if (auto vp = k in rhs.__hashes) {
                __hashes.put(k, HashMapElement(vp.value, p));
            }
        }
    }
    string toString() {
        import std.algorithm, std.array, std.format;

        auto pairs = byPair;
        return "[%s]".format(pairs.map!(p => "%s:%s".format(p.key, p.value)).array.join(", "));
    }

    ///
    auto put(K k, V v)
    {
        auto hashesptr = k in __hashes;
        if (hashesptr is null)
        {
            // append to list and store in hashes
            auto keysptr = __keys.insertBack(k);
            __hashes.put(k, HashMapElement(v, keysptr));
            return Nullable!V();
        }
        else
        {
            auto o = hashesptr.value;
            hashesptr.value = v;
            return nullable(o);
        }
    }
    ///
    /// map[key]
    /// Attention: you can't use this method in @nogc code.
    /// Usual aa[key] method.
    /// Throws exception if key not found
    /// Returns: value for given key
    ///
    ref V opIndex(in K k) @safe
    {
        V* v = k in this;
        if (v !is null)
        {
            return *v;
        }
        throw new KeyNotFound();
    }

    ///
    /// map[k] = v;
    ///
    void opIndexAssign(V v, K k) @safe
    {
        put(k, v);
    }
    ///
    bool remove(K k) @safe
    {
        auto hashesptr = k in __hashes;
        if (hashesptr is null)
        {
            return false;
        }
        auto keysptr = hashesptr.kptr;
        () @trusted { __keys.remove(keysptr); }();
        __hashes.remove(k);
        return true;
    }
    ///
    void clear() @safe
    {
        __hashes.clear();
        __keys.clear();
    }

    /// get numter of keys in table
    auto length() const pure nothrow @nogc @safe
    {
        return __keys.length;
    }

    /// key in table
    /// Returns: pointer to stored value (if key in table) or null 
    ///
    V* opBinaryRight(string op)(in K k) @safe if (op == "in")
    {
        auto hashesptr = k in __hashes;
        if (hashesptr)
        {
            return &hashesptr.value;
        }
        return null;
    }

    ///
    /// get
    /// Returns: value from hash, or defaultValue if key not found (see also getOrAdd).
    /// defaultValue can be callable.
    ///
    V get(T)(K k, T defaultValue) @safe
    {
        auto v = k in __hashes;
        if (v)
        {
            return v.value;
        }
        static if (isAssignable!(V, T))
        {
            return defaultValue;
        }
        else static if (isCallable!T && isAssignable!(V, ReturnType!T))
        {
            return defaultValue();
        }
        else
        {
            static assert(0, "You must call 'get' with default value of HashMap 'value' type, or with callable, returning HashMap 'value'");
        }
    }
    ///
    V getOrAdd(T)(K k, T defaultValue) @safe
    {
        auto v = k in __hashes;
        if (v)
        {
            return v.value;
        }
        static if (isAssignable!(V, T))
        {
            put(k, defaultValue);
            return defaultValue;
        }
        else static if (isCallable!T && isAssignable!(V, ReturnType!T))
        {
            auto value = defaultValue();
            return put(k, value);
            return value;
        }
        else
        {
            static assert(0, "what?");
        }
    }

    ///
    bool addIfMissed(T)(K k, T value) @safe {
        auto v = k in __hashes;
        if (v) {
            return false;
        }
        static if (isAssignable!(V, T)) {
            put(k, value);
            return true;
        }
        else static if (isCallable!T && isAssignable!(V, ReturnType!T)) {
            put(k, value());
            return true;
        }
        else {
            static assert(0, "what?");
        }
    }

    /// iterator by keys
    auto byKey() pure @safe @nogc
    {
        return __keys.range();
    }
    /// iterator by value
    auto byValue() pure @safe @nogc
    {
        struct _range
        {
            private KeysType.Range _keysIter;
            private HashesType* _hashes;
            V front() @safe
            {
                auto p = _keysIter.front in *_hashes;
                return p.value;
            }

            bool empty() @safe
            {
                return _keysIter.empty();
            }

            void popFront() @safe
            {
                _keysIter.popFront;
            }
        }

        return _range(__keys.range, &__hashes);
    }

    ///
    auto byPair() pure @safe @nogc
    {
        struct _range
        {
            private KeysType.Range _keysIter;
            private HashesType* _hashes;
            auto front() @safe
            {
                auto p = _keysIter.front in *_hashes;
                return Tuple!(K, "key", V, "value")(_keysIter.front, p.value);
            }

            bool empty() @safe
            {
                return _keysIter.empty();
            }

            void popFront() @safe
            {
                _keysIter.popFront;
            }
        }

        return _range(__keys.range, &__hashes);
    }
}

unittest {
    import std.experimental.logger;
    globalLogLevel = LogLevel.info;
    info("Testing OrderedHashMap");
}

@safe @nogc unittest
{
    import std.algorithm;
    import std.range;
    import std.stdio;
    OrderedHashMap!(int, int) dict;
    dict.put(1, 1);
    int* v = 1 in dict;
    assert(v !is null && *v == 1);
    assert(dict.remove(1));
    assert(1 !in dict);
    assert(!dict.remove(2));
    assert(dict.length == 0);
    iota(100).each!(a => dict.put(a, a));
    assert(dict.length == 100);
    assert(equal(dict.byKey, iota(100)));
    assert(equal(dict.byValue, iota(100)));
    assert(dict.getOrAdd(100, 100) == 100);
}

@safe @nogc unittest {
    import std.algorithm;
    import std.range;

    OrderedHashMap!(int, int) dict0, dict1;
    iota(100).each!(a => dict0.put(a, a));
    dict1 = dict0;
    assert(0 in dict1);
    dict1.remove(0);
    assert(equal(dict1.byKey, iota(1,100)));
}

@safe unittest {
    class C {
        hash_t c;
        override hash_t toHash() const @safe {
            return c;
        }

        bool opEquals(const C other) const @safe {
            return c == other.c;
        }

        this(hash_t i) {
            c = i;
        }
        // void opCast(const C from) {
        //     c = from.c;
        // }
    }

    OrderedHashMap!(C, int) map;
    int* f(const C c) {
        auto v = map[c];
        // can't do this with classes because put require key assignment which can't convert const object to mutable
        //map.put(c, 2);
        return c in map;
    }

    C c = new C(1);
    map[c] = 1;
    f(c);
}