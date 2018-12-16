module cachetools.cachelru;

import std.typecons;
import std.exception;
import core.stdc.time;

private import std.experimental.allocator;
private import std.experimental.allocator.mallocator : Mallocator;

private import cachetools.internal;
private import cachetools.interfaces;
private import cachetools.containers.hashmap;
private import cachetools.containers.lists;

///
/// CacheLRU contains maximum `size` items
/// Eviction policy:
/// 1. evict TTL-ed entry (if TTL enabled), otherwise
/// 2. if oldest entry not expired - evict oldes accessed (LRU)
///
/// User can be informed about evicted entries via cache event list.
///

class CacheLRU(K, V, Allocator = Mallocator) {
    ///
    /// Implemented as HashMap and multi-dlist.
    ///
    /// HashMap (by key) keep 
    ///  1. cached value
    ///  2. pointer to dlist element.
    ///  3. creation time (to check expiration and purge expired entry on get() without access to dlist)
    ///  4. hits counter
    ///
    /// dlist keep key, cteation timestamp (to check expiration)
    ///  1. key, so that we can remove entries from hashmap for lists heads (AccessIndex and TimeIndex)
    ///  2. creation time, so that we can check expiration for 'TimeIndex'
    ///
    /// Each element in dlist have two sets of double-links - first set create order by access time, second set
    /// for creation time.
    ///
    private {
        enum size_t AccessIndex = 0;
        enum size_t TimeIndex = 1;
        struct ListElement {
            K key; // we keep key here so we can remove element from map when we evict with LRU or TTL)
            time_t ts; // creation (we keep it here to check expiration for oldest element)
        }

        struct MapElement {
            StoredType!V value; // value
            //ushort              hits;   // accesses
            time_t ts; // creation (wee keep it here to check expiration on access)
            ListElementPtr list_element_ptr;
        }

        alias allocator = Allocator.instance;
        alias ListElementPtr = __elements.Node*;

        MultiDList!(ListElement, 2, Allocator) __elements; // keeps order by creation time and by access time
        HashMap!(K, MapElement, Allocator) __map; // keeps MapElement by key
        SList!(CacheEvent!(K, V), Allocator) __events; // unbounded list of cache events

        // configuration
        size_t __size = 1024; // limit num of elements in cache
        uint __ttl; // use TTL if __ttl > 0
        bool __reportCacheEvents; // will user read cache events?
    }
    struct CacheEventRange(K, V) {
        SList!(CacheEvent!(K, V), Allocator) __events;
        this(ref SList!(CacheEvent!(K, V), Allocator) events) {
            import std.algorithm.mutation : swap;

            swap(__events, events);
        }

        bool empty() const nothrow pure {
            return __events.empty();
        }

        void popFront() pure nothrow {
            __events.popFront();
        }

        auto front() {
            return __events.front();
        }

        auto length() pure const nothrow @safe {
            return __events.length;
        }
    }

    final Nullable!V get(K k) @safe {
        debug (cachetools)
            safe_tracef("get %s", k);
        auto store_ptr = k in __map;
        if (!store_ptr) {
            return Nullable!V();
        }
        if (__ttl > 0 && time(null) - store_ptr.ts >= __ttl) {
            // remove expired entry
            if (__reportCacheEvents) {
                // store in event list
                CacheEvent!(K, V) cache_event = {
                    EventType.Expired, k, store_ptr.value
                };
                __events.insertBack(cache_event);
            }
            // and remove from storage and list
            __map.remove(k);
            __elements.remove(store_ptr.list_element_ptr);
            return Nullable!V();
        }
        //store_ptr.hits++;
        auto order_p = store_ptr.list_element_ptr;
        __elements.move_to_tail(order_p, AccessIndex);
        return Nullable!V(store_ptr.value);
    }

    final PutResult put(K k, V v) @safe
    out {
        assert(__result != PutResult(PutResultFlag.None));
    }
    do {
        time_t ts = time(null);
        PutResult result;
        auto store_ptr = k in __map;
        if (!store_ptr) // insert element
        {
            result = PutResultFlag.Inserted;
            if (__elements.length >= __size) {
                ListElementPtr e;
                // we have to purge
                // 1. check if oldest element is ttled
                if (__ttl > 0 && ts - __elements.head(TimeIndex).ts >= __ttl) {
                    // purge ttl-ed element
                    e = __elements.head(TimeIndex);
                    debug (cachetools)
                        safe_tracef("purging ttled %s", *e);
                } else {
                    // purge lru element
                    e = __elements.head(AccessIndex);
                    debug (cachetools)
                        safe_tracef("purging lru %s", *e);
                }
                assert(e !is null);
                if (__reportCacheEvents) {
                    auto value_ptr = e.key in __map;
                    CacheEvent!(K, V) cache_event = {
                        EventType.Evicted, e.key, value_ptr.value
                    };
                    __events.insertBack(cache_event);
                }
                __map.remove(e.key);
                __elements.remove(e);
                result |= PutResultFlag.Evicted;
            }
            auto order_node = __elements.insert_last(ListElement(k, ts));
            MapElement e = {value:
            v, ts : ts, list_element_ptr : order_node};
            __map.put(k, e);
        } else // update element
        {
            result = PutResultFlag.Replaced;
            debug (cachetools)
                safe_tracef("update %s", *store_ptr);
            ListElementPtr e = store_ptr.list_element_ptr;
            e.ts = ts;
            __elements.move_to_tail(e, TimeIndex);
            if (__reportCacheEvents) {
                auto v_ptr = e.key in __map;
                CacheEvent!(K, V) cache_event = {
                    EventType.Updated, e.key, v_ptr.value
                };
                __events.insertBack(cache_event);
            }
            store_ptr.value = v;
            store_ptr.ts = ts;
        }
        return result;
    }

    final bool remove(K k) @safe {
        debug (cachetools)
            safe_tracef("remove from cache %s", k);
        auto map_ptr = k in __map;
        if (!map_ptr) // do nothing
        {
            return false;
        }
        ListElementPtr e = map_ptr.list_element_ptr;
        if (__reportCacheEvents) {
            auto v_ptr = e.key in __map;
            CacheEvent!(K, V) cache_event = {
                EventType.Removed, e.key, v_ptr.value
            };
            __events.insertBack(cache_event);
        }
        __map.remove(e.key);
        __elements.remove(e);
        return true;
    }

    final void clear() @safe {
        if (__reportCacheEvents) {
            foreach (pair; __map.byPair) {
                CacheEvent!(K, V) cache_event = {
                    EventType.Removed, pair.key, pair.value.value
                };
                __events.insertBack(cache_event);
            }
        }
        __map.clear();
        __elements.clear();
    }

    size_t length() pure nothrow const @safe @nogc {
        return __elements.length;
    }

    auto size(size_t s) pure nothrow @safe @nogc {
        __size = s;
        return this;
    }

    size_t size() pure nothrow const @safe @nogc {
        return __size;
    }

    auto ttl(uint d) pure nothrow @safe @nogc {
        __ttl = d;
        return this;
    }

    uint ttl() pure nothrow const @safe @nogc {
        return __ttl;
    }

    auto enableCacheEvents() pure nothrow @safe @nogc {
        __reportCacheEvents = true;
        return this;
    }

    final auto cacheEvents() @safe {
        return CacheEventRange!(K, V)(__events);
    }
}

@safe unittest {
    import std.stdio;
    import std.datetime;
    import core.thread;
    import std.algorithm;
    import std.experimental.logger;

    globalLogLevel = LogLevel.info;
    info("Testing LRU");
    PutResult r;

    auto lru = new CacheLRU!(int, string);
    lru.size(4).ttl(1).enableCacheEvents();
    assert(lru.size == 4);
    assert(lru.ttl == 1);

    assert(lru.length == 0);
    r = lru.put(1, "one");
    assert(r == PutResult(PutResultFlag.Inserted));
    r = lru.put(2, "two");
    assert(r == PutResult(PutResultFlag.Inserted));
    auto v = lru.get(1);
    assert(v == "one");
    r = lru.put(3, "three");
    assert(r & PutResultFlag.Inserted);
    r = lru.put(4, "four");
    assert(r & PutResultFlag.Inserted);
    assert(lru.length == 4);
    // next put should purge...
    r = lru.put(5, "five");
    assert(r == PutResult(PutResultFlag.Evicted, PutResultFlag.Inserted));
    () @trusted { Thread.sleep(2.seconds); }();
    v = lru.get(1); // it must be expired by ttl
    assert(v.isNull);
    assert(lru.length == 3);
    r = lru.put(6, "six");
    assert(r == PutResult(PutResultFlag.Inserted));
    assert(lru.length == 4);
    r = lru.put(7, "seven");
    assert(r == PutResult(PutResultFlag.Evicted, PutResultFlag.Inserted));
    assert(lru.length == 4);
    lru.put(7, "7");
    assert(lru.length == 4);
    assert(lru.get(7) == "7");
    lru.clear();
    assert(lru.length == 0);
    assert(lru.get(7).isNull);
    auto events = lru.cacheEvents();
    assert(!events.empty);
    assert(events.length() == 8);
    assert(lru.__events.empty);
    assert(equal(events.map!"a.key", [2, 1, 3, 7, 6, 7, 5, 4]));
    assert(equal(events.map!"a.val", ["two", "one", "three", "seven", "six", "7", "five", "four"]));
}

// check if we can cache with immutable struct keys
@safe unittest {
    struct S {
        int s;
    }

    CacheLRU!(immutable S, string) cache = new CacheLRU!(immutable S, string);
    immutable S s1 = immutable S(1);
    cache.put(s1, "one");
    auto s11 = cache.get(s1);
    assert(s11 == "one");
    assert(cache.remove(s1));
    assert(!cache.remove(S(2)));
}

// check if we can cache with immutable struct values
@safe unittest {
    struct S {
        int s;
    }

    auto cache = new CacheLRU!(string, immutable S);
    immutable S s1 = immutable S(1);
    cache.put("one", s1);
    auto s11 = cache.get("one");
    assert(s11 == s1);
    immutable S s12 = immutable S(12);
    cache.put("one", s12);
    auto s121 = cache.get("one");
    assert(s121 == s12);
}

// check if we can cache with immutable class keys and values
@safe unittest {
    import cachetools.hash : hash_function;

    class C {
        int s;
        this(int v) {
            s = v;
        }

        override hash_t toHash() const {
            return hash_function(s);
        }

        bool opEquals(const C other) pure const @safe {
            auto i = [1, 2];
            return s == other.s;
        }
    }

    CacheLRU!(immutable C, string) ick = new CacheLRU!(immutable C, string);
    immutable C s1 = new immutable C(1);
    ick.put(s1, "one");
    auto s11 = ick.get(s1);
    assert(s11 == "one");

    CacheLRU!(string, immutable C) icv = new CacheLRU!(string, immutable C);
    immutable C s1v = new immutable C(1);
    icv.put("one", s1v);
    auto s11v = icv.get("one");
    assert(s11v is s1v);
}

///
@nogc nothrow unittest {
    import std.experimental.allocator.mallocator;

    alias allocator = Mallocator.instance;
    alias Cache = CacheLRU!(int, string);

    auto lru = make!(Cache)(allocator);

    lru.size = 2048; // keep 2048 elements in cache
    lru.ttl = 60; // set 60 seconds TTL for items in cache

    lru.put(1, "one");
    auto v = lru.get(0);
    assert(v.isNull); // no such item in cache
    v = lru.get(1);
    assert(v == "one"); // 1 is in cache
    lru.remove(1);
}

@safe nothrow unittest {
    auto lru = new CacheLRU!(int, string);
    () @nogc {
        lru.enableCacheEvents();
        lru.put(1, "one");
        lru.put(1, "next one");
        assert(lru.get(1) == "next one");
        auto events = lru.cacheEvents();
        assert(events.length == 1);
        lru.clear();
    }();
}
