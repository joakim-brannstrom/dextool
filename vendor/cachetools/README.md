[![Build Status](https://travis-ci.org/ikod/cachetools.svg?branch=master)](https://travis-ci.org/ikod/cachetools)
[![codecov.io](https://codecov.io/github/ikod/cachetools/coverage.svg?branch=master)](https://codecov.io/github/ikod/cachetools?branch=master)
[![Dub downloads](https://img.shields.io/dub/dt/cachetools.svg)](http://code.dlang.org/packages/cachetools)
# cachetools #

This package contains some cache implementations (for example LRU cache) and underlying data structures.

Why you may want to use it? Because it is fast, `@safe`. It is also `@nogc` and `nothrow` (inherited from your key/value types).

Limitations:
* Cache implementations are not inherited from inerface or base class.
This is because inheritance and attribute inference don't work together.

### LRU cache ###

LRU cache keep limited number of items in memory. When adding new item to already full cache we have to evict some items.
Eviction candidates are selected first from expired items (using per-cache configurable TTL) or from oldest accessed items.

## Code examples ##

```d
    auto lru = new CacheLRU!(int, string);
    lru.size = 2048; // keep 2048 elements in cache
    lru.ttl = 60;    // set 60 seconds TTL for items in cache
    
    lru.put(1, "one");
    auto v = lru.get(1);
    assert(v == "one"); // 1 is in cache
    v = lru.get(2);
    assert(v.isNull);   // no such item in cache

```

Default values for TTL is 0 which means - no TTL. Default value for size is 1024;

### Class instance as key ###

To use class as key with this code, you have to define toHash and opEquals(**important**: opEquals to the class instance not Object) as safe or trusted (optionally as nogc if
you need it):

```d
    import cachetools.hash: hash_function;
    class C
    {
        int s;
        this(int v)
        {
            s = v;
        }
        override hash_t toHash() const
        {
            return hash_function(s);
        }
        bool opEquals(const C other) pure const @safe
        {
            return s == other.s;
        }
    }
    CacheLRU!(immutable C, string) cache = new CacheLRU!(immutable C, string);
    immutable C s1 = new immutable C(1);
    cache.put(s1, "one");
    auto s11 = cache.get(s1);
    assert(s11 == "one");

```

### Cache events ###

Sometimes you have to know if items are purged from cache or modified. You can configure cache to report such events.
*Important warning* - if you enable cache events and do not check it after cache operations, then list of stored events will
grow without bounds. Code sample:
```d

    auto lru = new CacheLRU!(int, string);
    lru.enableCacheEvents();
    lru.put(1, "one");
    lru.put(1, "next one");
    assert(lru.get(1) == "next one");
    auto events = lru.cacheEvents();
    writeln(events);

```
output:
```
[CacheEvent!(int, string)(Updated, 1, "one")]
```
Each `CacheEvent` have `key` and `val` members and name of the event(Removed, Expired, Changed, Evicted).

## Hash Table ##

Some parts of this package are based on internal hash table which can be used independently. It is open-addressing
hash table with keys and values stored inline in the buckets array to avoid unnecessary allocations and better use 
of CPU cache for small key/value types.

Hash Table supports immutable keys and values. Due to language limitations you can't use structs with immutable/const
members.

All hash table code is `@safe` and require from user supplied functions such as `toHash` or `opEquals` also be safe (or trusted).

It is also `@nogc` if `toHash` and `opEquals` are `@nogc`. `opIndex` is not `@nogc` as it can throw exception.

Several code samples:

```d
import cachetools.containers.hashmap;

string[] words = ["hello", "my", "friend", "hello"];

void main()
{
    HashMap!(string, int) counter;

    build0(counter); // build table (verbose variant)
    report(counter);

    counter.clear(); // clear table

    build1(counter); // build table (less verbose variant)
    report(counter);
}

/// verbose variant
void build0(ref HashMap!(string, int) counter) @safe @nogc
{
    foreach(word; words)
    {
        auto w = word in counter;
        if ( w !is null )
        {
            (*w)++; // update
        }
        else
        {
            counter[word] = 1; // create
        }
    }
}
/// short variant
void build1(ref HashMap!(string, int) counter) @safe @nogc
{
    foreach(word; words)
    {
        auto w = word in counter;
        counter.getOrAdd(word, 0)++;
    }
}

void report(ref HashMap!(string, int) hashmap) @safe
{
    import std.stdio;
    writefln("keys: %s", hashmap.byKey);
    writefln("values: %s", hashmap.byValue);
    writefln("pairs: %s", hashmap.byPair);
    writeln("---");
}
```
Output:
```
keys: ["hello", "friend", "my"]
values: [2, 1, 1]
pairs: [Tuple!(string, "key", int, "value")("hello", 2), Tuple!(string, "key", int, "value")("friend", 1), Tuple!(string, "key", int, "value")("my", 1)]
---
keys: ["hello", "friend", "my"]
values: [2, 1, 1]
pairs: [Tuple!(string, "key", int, "value")("hello", 2), Tuple!(string, "key", int, "value")("friend", 1), Tuple!(string, "key", int, "value")("my", 1)]
---
```