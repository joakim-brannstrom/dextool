/**
    2Q cache is variant of multi-level LRU cache. Original paper http://www.vldb.org/conf/1994/P439.PDF
    It is adaptive, scan-resistant and can give more hits than plain LRU.
    $(P This cache consists from three parts (In, Out and Main) where 'In' receive all new elements, 'Out' receives all
    overflows from 'In', and 'Main' is LRU cache which hold all long-lived data.)
**/
module cachetools.cache2q;

/// Implements Q2 cache
/// http://www.vldb.org/conf/1994/P439.PDF

private import std.experimental.allocator;
private import std.experimental.allocator.mallocator : Mallocator;
private import std.typecons;

private import cachetools.internal;
private import cachetools.interfaces;
private import cachetools.containers.hashmap;
private import cachetools.containers.lists;

/* Pseudocode from the paper
// If there is space, we give it to X.
// If there is no space, we free a page slot to
// make room for page X.
reclaimfor(page X)
    begin
        if there are free page slots then
            put X into a free page slot
        else if( |Alin| > Kin)
            page out the tail of Alin, call it Y
            add identifier of Y to the head of Alout
            if(]Alout] >Kout)
                remove identifier of Z from
                the tail of Alout
            end if
            put X into the reclaimed page slot
        else
            page out the tail of Am, call it Y
            // do not put it on Alout; it hasn’t been
            // accessed for a while
            put X into the reclaimed page slot
        end if
end

On accessing a page X :
begin
    if X is in Am then
        move X to the head of Am
    else if (X is in Alout) then
        reclaimfor(Х)
        add X to the head of Am
    else if (X is in Alin) // do nothing
    else // X is in no queue
        reclaimfor(X)
        add X to the head of Alin
    end if
end 
*/


///
class Cache2Q(K, V, Allocator=Mallocator)
{
    private
    {
        private import core.time;

        private alias TimeType = MonoTimeImpl!(ClockType.coarse);

        struct ListElement {
            StoredType!K        key;    // we keep key here so we can remove element from map when we evict with LRU or TTL)
        }
        alias ListType = CompressedList!(ListElement, Allocator);
        alias ListElementPtrType = ListType.NodePointer;
        alias DListType = DList!(ListElement, Allocator);
        alias DListElementPtrType = DListType.Node!ListElement*;

        struct MapElement
        {
            StoredType!V        value;
            ListElementPtrType  list_element_ptr;
            TimeType            expired_at;
        }
        struct MainMapElement
        {
            StoredType!V         value;
            DListElementPtrType  list_element_ptr;
            TimeType             expired_at;
        }

        int _kin, _kout, _km;

        CompressedList!(ListElement, Allocator)     _InList;
        CompressedList!(ListElement, Allocator)     _OutList;
        DList!(ListElement, Allocator)              _MainList;

        HashMap!(K, MapElement, Allocator)          _InMap;
        HashMap!(K, MapElement, Allocator)          _OutMap;
        HashMap!(K, MainMapElement, Allocator)      _MainMap;

        Duration                                    _ttl; // global ttl (if > 0)

        bool                                        __reportCacheEvents;
        SList!(CacheEvent!(K, V), Allocator)        __events; // unbounded list of cache events

    }
    final this() @safe {
        _kin = 1080 / 6;
        _kout = 1080 / 6;
        _km = 2 * 1080 / 3;
        _InMap.grow_factor(4);
        _OutMap.grow_factor(4);
        _MainMap.grow_factor(4);
    }
    final this(int s) @safe {
        _kin = s/6;
        _kout = s/6;
        _km = 2*s/3;
        _InMap.grow_factor(4);
        _OutMap.grow_factor(4);
        _MainMap.grow_factor(4);
    }
    ///
    /// Set total cache size. 'In' and 'Out' gets 1/6 of total size, Main gets 2/3 of size.
    ///
    final auto size(uint s) @safe
    {
        _kin =  1*s/6;
        _kout = 1*s/6;
        _km =   4*s/6;
        return this;
    }
    ///
    /// Set In queue size
    ///
    final auto sizeIn(uint s) @safe
    {
        _kin =  s;
        return this;
    }

    ///
    /// Set Out queue size
    ///
    final auto sizeOut(uint s) @safe
    {
        _kout =  s;
        return this;
    }

    ///
    /// Set Main queue size
    ///
    final auto sizeMain(uint s) @safe
    {
        _km =  s;
        return this;
    }

    ///
    /// Number of elements in cache.
    ///
    final int length() @safe
    {
        return _InMap.length + _OutMap.length + _MainMap.length;
    }
    ///
    /// Drop all elements from cache.
    ///
    final void clear()
    {
        _InList.clear();
        _OutList.clear();
        _MainList.clear();
        if ( __reportCacheEvents ) {
            foreach(p; _InMap.byPair) {
                __events.insertBack(CacheEvent!(K, V)(EventType.Removed, p.key, p.value.value));
            }
            foreach(p; _OutMap.byPair){
                __events.insertBack(CacheEvent!(K, V)(EventType.Removed, p.key, p.value.value));
            }
            foreach(p; _MainMap.byPair){
                __events.insertBack(CacheEvent!(K, V)(EventType.Removed, p.key, p.value.value));
            }
        }
        _InMap.clear();
        _OutMap.clear();
        _MainMap.clear();
    }
    ///
    /// Set default ttl (seconds)
    ///
    final void ttl(Duration v) @safe
    {
        _ttl = v;
    }
    deprecated("Use ttl(Duration)")
    final void ttl(int v) @safe
    {
        _ttl = v.seconds;
    }
    ///
    auto enableCacheEvents() pure nothrow @safe @nogc
    {
        __reportCacheEvents = true;
        return this;
    }
    ///
    final auto cacheEvents()
    {
        auto r = CacheEventRange!(K, V)(__events);
        __events.clear;
        return r;
    }

    struct CacheEventRange(K, V)
    {

        private SList!(CacheEvent!(K, V), Allocator) __events;

        void opAssign(CacheEventRange!(K, V) other)
        {
            __events.clear();
            __events = other.__events;
        }

        this(ref SList!(CacheEvent!(K, V), Allocator) events)
        {
            __events = events;
        }

        bool empty() const nothrow @safe
        {
            return __events.empty();
        }

        void popFront() nothrow
        {
            __events.popFront();
        }

        auto front() @safe
        {
            return __events.front();
        }

        auto length() pure const nothrow @safe
        {
            return __events.length;
        }
        auto save() {
            return CacheEventRange!(K, V)(__events);
        }
    }
    ///
    /// Get element from cache.
    ///
    final Nullable!V get(K k)
    {
        debug(cachetools) safe_tracef("get %s", k);

        MainMapElement* keyInMain = k in _MainMap;
        if ( keyInMain )
        {
            debug(cachetools) safe_tracef("%s in main cache: %s", k, *keyInMain);
            if ( keyInMain.expired_at > TimeType.init && keyInMain.expired_at <= TimeType.currTime ) 
            {
                // expired
                if (__reportCacheEvents)
                {
                    __events.insertBack(CacheEvent!(K, V)(EventType.Expired, k, keyInMain.value));
                }
                _MainList.remove(keyInMain.list_element_ptr);
                _MainMap.remove(k);
                return Nullable!V();
            }
            _MainList.move_to_head(keyInMain.list_element_ptr);
            return Nullable!V(keyInMain.value);
        }
        debug(cachetools) safe_tracef("%s not in main cache", k);

        auto keyInOut = k in _OutMap;
        if ( keyInOut )
        {
            debug(cachetools) safe_tracef("%s in A1Out cache: %s", k, *keyInOut);
            if (keyInOut.expired_at > TimeType.init && keyInOut.expired_at <= TimeType.currTime)
            {
                // expired
                if (__reportCacheEvents)
                {
                    __events.insertBack(CacheEvent!(K, V)(EventType.Expired, k, keyInOut.value));
                }
                delegate void() @trusted {
                    _OutList.remove(keyInOut.list_element_ptr);
                }();
                _OutMap.remove(k);
                return Nullable!V();
            }
            // move from Out to Main
            auto value = keyInOut.value;
            auto expired_at = keyInOut.expired_at;

            delegate void() @trusted
            {
                assert((*keyInOut.list_element_ptr).key == k);
                _OutList.remove(keyInOut.list_element_ptr);
            }();

            bool removed = _OutMap.remove(k);
            assert(removed);
            debug(cachetools) safe_tracef("%s removed from A1Out cache", k);

            auto mlp = _MainList.insertFront(ListElement(k));
            _MainMap.put(k, MainMapElement(value, mlp, expired_at));
            debug(cachetools) safe_tracef("%s placed to Main cache", k);
            if ( _MainList.length > _km )
            {
                debug(cachetools) safe_tracef("Main cache overflowed, pop %s", _MainList.tail().key);
                if (__reportCacheEvents)
                {
                    auto key_to_evict = _MainList.tail().key;
                    auto mptr = key_to_evict in _MainMap;
                    __events.insertBack(CacheEvent!(K, V)(EventType.Evicted, key_to_evict, mptr.value));
                }
                _MainMap.remove(_MainList.tail().key);
                _MainList.popBack();
            }
            return Nullable!V(value);
        }
        debug(cachetools) safe_tracef("%s not in Out cache", k);

        auto keyInIn = k in _InMap;
        if ( keyInIn )
        {
            debug(cachetools) safe_tracef("%s in In cache", k);
            if (keyInIn.expired_at > TimeType.init && keyInIn.expired_at <= TimeType.currTime)
            {
                // expired
                if (__reportCacheEvents) {
                    __events.insertBack(CacheEvent!(K, V)(EventType.Expired, k, keyInIn.value));
                }
                delegate void () @trusted {
                    _InList.remove(keyInIn.list_element_ptr);
                }();
                _InMap.remove(k);
                return Nullable!V();
            }
            // just return value
            return Nullable!V(keyInIn.value);
        }
        debug(cachetools) safe_tracef("%s not in In cache", k);

        return Nullable!V();
    }

    ///
    /// Put element to cache.
    ///
    /// Evict something if we have to.
    ///
    final PutResult put(K k, V v, TTL ttl = TTL())
    out
    {
        assert(__result != PutResult(PutResultFlag.None));
    }
    do
    {
        TimeType exp_time;

        if ( _ttl > 0.seconds && ttl.useDefault  ) {
            exp_time = TimeType.currTime + _ttl;
        }

        if ( ttl.value > 0.seconds ) {
            exp_time = TimeType.currTime + ttl.value;
        }

        auto keyInMain = k in _MainMap;
        if ( keyInMain )
        {
            if ( __reportCacheEvents ) {
                __events.insertBack(CacheEvent!(K, V)(EventType.Updated, k, keyInMain.value));
            }
            keyInMain.value = v;
            keyInMain.expired_at = exp_time;
            debug(cachetools) safe_tracef("%s in Main cache", k);
            return PutResult(PutResultFlag.Replaced);
        }
        debug(cachetools) safe_tracef("%s not in Main cache", k);

        auto keyInOut = k in _OutMap;
        if ( keyInOut )
        {
            if ( __reportCacheEvents ) {
                __events.insertBack(CacheEvent!(K, V)(EventType.Updated, k, keyInOut.value));
            }
            keyInOut.value = v;
            keyInOut.expired_at = exp_time;
            debug(cachetools) safe_tracef("%s in Out cache", k);
            return PutResult(PutResultFlag.Replaced);
        }
        debug(cachetools) safe_tracef("%s not in Out cache", k);

        auto keyInIn = k in _InMap;
        if ( keyInIn )
        {
            if ( __reportCacheEvents ) {
                __events.insertBack(CacheEvent!(K, V)(EventType.Updated, k, keyInIn.value));
            }
            keyInIn.value = v;
            keyInIn.expired_at = exp_time;
            debug(cachetools) safe_tracef("%s in In cache", k);
            return PutResult(PutResultFlag.Replaced);
        }
        else
        {
            debug(cachetools) safe_tracef("insert %s in A1InFifo", k);
            auto lp = _InList.insertBack(ListElement(k));
            _InMap.put(k, MapElement(v, lp, exp_time));
            if ( _InList.length <= _kin )
            {
                return PutResult(PutResultFlag.Inserted);
            }

            debug(cachetools) safe_tracef("pop %s from InLlist", _InList.front.key);

            auto toOutK = _InList.front.key;
            _InList.popFront();

            auto in_ptr = toOutK in _InMap;

            auto toOutV = in_ptr.value;
            auto toOutE = in_ptr.expired_at;
            bool removed = _InMap.remove(toOutK);

            assert(removed);
            assert(_InList.length == _InMap.length);

            if ( toOutE > TimeType.init && toOutE <= TimeType.currTime )
            {
                // expired, we done
                if (__reportCacheEvents) {
                    __events.insertBack(CacheEvent!(K, V)(EventType.Expired, toOutK, toOutV));
                }
                return PutResult(PutResultFlag.Inserted|PutResultFlag.Evicted);
            }

            // and push to Out
            lp = _OutList.insertBack(ListElement(toOutK));
            _OutMap.put(toOutK, MapElement(toOutV, lp, toOutE));
            if ( _OutList.length <= _kout )
            {
                return PutResult(PutResultFlag.Inserted|PutResultFlag.Evicted);
            }
            //
            // Out overflowed - throw away head
            //
            debug(cachetools) safe_tracef("pop %s from Out", _OutList.front.key);

            if (__reportCacheEvents)
            {
                // store in event list
                auto evicted_key = _OutList.front.key;
                auto mptr = evicted_key in _OutMap;
                __events.insertBack(CacheEvent!(K,V)(EventType.Evicted, evicted_key, mptr.value));
            }

            removed = _OutMap.remove(_OutList.front.key);
            _OutList.popFront();

            assert(removed);
            assert(_OutList.length == _OutMap.length);

            return PutResult(PutResultFlag.Inserted|PutResultFlag.Evicted);
        }
    }
    ///
    /// Remove element from cache.
    ///
    final bool remove(K k)
    {
        debug(cachetools) safe_tracef("remove from 2qcache key %s", k);
        auto inIn = k in _InMap;
        if ( inIn )
        {
            auto lp = inIn.list_element_ptr;

            if (__reportCacheEvents)
            {
                __events.insertBack(CacheEvent!(K, V)(EventType.Removed, k, inIn.value));
            }

            () @trusted
            {
                _InList.remove(lp);
            }();
            _InMap.remove(k);
            return true;
        }
        auto inOut = k in _OutMap;
        if ( inOut )
        {

            if (__reportCacheEvents)
            {
                __events.insertBack(CacheEvent!(K, V)(EventType.Removed, k, inOut.value));
            }

            auto lp = inOut.list_element_ptr;
            () @trusted
            {
                _OutList.remove(lp);
            }();
            _OutMap.remove(k);
            return true;
        }
        auto inMain = k in _MainMap;
        if ( inMain )
        {

            if (__reportCacheEvents)
            {
                __events.insertBack(CacheEvent!(K, V)(EventType.Removed, k, inMain.value));
            }

            auto lp = inMain.list_element_ptr;
            _MainList.remove(lp);
            _MainMap.remove(k);
            return true;
        }
        return false;
    }
}

@safe unittest
{
    import std.stdio, std.format;
    import std.datetime;
    import core.thread;
    import std.algorithm;
    import std.experimental.logger;
    globalLogLevel = LogLevel.info;
    info("Testing 2Q");
    auto cache = new Cache2Q!(int, int);
    cache.size = 12;
    foreach(i;0..11)
    {
        cache.put(i,i);
        cache.get(i-3);
    }
    cache.put(11,11);
    // In:   [11, 10]
    // Out:  [8, 9]
    // Main: [0, 6, 7, 2, 3, 1, 5, 4]
    assert(cache._InMap.length == 2);
    assert(cache._OutMap.length == 2);
    assert(cache._MainMap.length == 8);
    assert(cache.length==12, "expected 12, got %d".format(cache.length));
    foreach(i;0..12)
    {
        assert(cache.get(i) == i, "missed %s".format(i));
    }
    cache.clear();
    assert(cache.length==0);
    foreach(i;0..11)
    {
        cache.put(i,i);
        cache.get(i-3);
    }
    cache.put(11,11);
    foreach(i;0..12)
    {
        assert(cache.remove(i), "failed to remove %s".format(i));
    }
    assert(cache.length==0);
    foreach(i;0..11)
    {
        cache.put(i,i);
        cache.get(i-3);
    }
    cache.put(11,11);
    // In:   [11, 10]
    // Out:  [8, 9]
    // Main: [0, 6, 7, 2, 3, 1, 5, 4]
    cache.put(11,22);
    cache.put(8, 88);
    cache.put(5,55);
    assert(cache.get(5) == 55);
    assert(cache.get(11) == 22);
    assert(cache.length==12, "expected 12, got %d".format(cache.length));
    assert(cache.get(8) == 88); // 8 moved from Out to Main
    assert(cache.length==11, "expected 11, got %d".format(cache.length));
    cache.put(12,12);   // in iverflowed, out filled
    cache.put(13, 13);  // in overflowed, out overflowed to main
    assert(cache.length==12, "expected 12, got %d".format(cache.length));
    globalLogLevel = LogLevel.info;
}

unittest
{
    // testing ttl
    import std.stdio, std.format;
    import std.datetime;
    import std.range;
    import std.algorithm;
    import core.thread;
    import std.experimental.logger;

    globalLogLevel = LogLevel.info;
    auto cache = new Cache2Q!(int, int);
    cache.sizeIn = 2;
    cache.sizeOut = 2;
    cache.sizeMain = 4;
    cache.enableCacheEvents;

    cache.put(1, 1, TTL(1.seconds));
    cache.put(2, 2, TTL(1.seconds));
    // in: 1, 2
    cache.put(3,3);
    cache.put(4,4);
    // in: 3, 4
    // out 1, 2
    cache.get(1);
    // in: 3, 4
    // out 2
    // main: 1
    cache.put(5,5, TTL(1.seconds));
    // In: 4(-), 5(1)   //
    // Out: 2(1), 3(-)  // TTL in parens
    // Main: 1(1)       //
    assert(4 in cache._InMap && 5 in cache._InMap);
    assert(2 in cache._OutMap && 3 in cache._OutMap);
    assert(1 in cache._MainMap);
    Thread.sleep(1500.msecs);
    assert(cache.get(1).isNull);
    assert(cache.get(2).isNull);
    assert(cache.get(5).isNull);
    assert(cache.get(3) == 3);
    assert(cache.get(4) == 4);
    cache.clear;
    auto e = cache.cacheEvents;
    assert(e.filter!(a => a.event == EventType.Removed).count == 2);
    assert(e.filter!(a => a.event == EventType.Expired).count == 3);
    cache.ttl = 1.seconds;
    cache.put(1, 1);            // default TTL - this must not survive 1s sleep
    cache.put(2, 2, ~TTL());    // no TTL, ignore default - this must survive any time 
    cache.put(3, 3, TTL(2.seconds));    // set TTL for this item - this must not survive 2s
    Thread.sleep(1200.msecs);
    assert(cache.get(1).isNull); // expired
    assert(cache.get(2) == 2);
    assert(cache.get(3) == 3);
    Thread.sleep(1000.msecs);
    assert(cache.get(2) == 2);
    assert(cache.get(3).isNull); // expired
    e = cache.cacheEvents;
    assert(e.map!(a => a.event).all!(a => a == EventType.Expired));
    cache.remove(2);
    e = cache.cacheEvents;
    assert(e.length == 1 && e.front.key == 2);
    // test cache events after clear
    cache.sizeIn = 10;
    iota(5).each!(i => cache.put(i,i));
    cache.clear;
    e = cache.cacheEvents;
    assert(e.length == 5);
    assert(e.map!(a => a.event).all!(a => a == EventType.Removed));

    // test for clear from all queues
    cache.sizeIn = 2;
    cache.sizeOut = 2;
    cache.sizeMain = 1;
    cache.ttl = 0.seconds;
    cache.put(1, 1);
    cache.put(2, 2);
    // in: 1, 2
    cache.put(3, 3);
    cache.put(4, 4);
    // in: 3, 4
    // out 1, 2
    cache.get(1);
    // in: 3, 4
    // out 2
    // main: 1
    cache.put(5, 5);
    // In: 4, 5
    // Out: 2, 3
    // Main: 1
    cache.clear;
    e = cache.cacheEvents;
    assert(e.length == 5);
    // test for eviction events from all queues
    cache.put(1, 1);
    cache.put(2, 2);
    // in: 1, 2
    cache.put(3, 3);
    cache.put(4, 4);
    // in: 3, 4
    // out 1, 2
    cache.get(1);
    // in: 3, 4
    // out 2
    // main: 1
    cache.put(5, 5);
    // In: 4, 5
    // Out: 2, 3
    // Main: 1
    cache.get(2); // 1 evicted and replaced by 2
    // In: 4, 5
    // Out: 3
    // Main: 2
    e = cache.cacheEvents;
    assert(e.length == 1);
    assert(e.front.key == 1);
    assert(e.front.event == EventType.Evicted);
    cache.put(4, 44, TTL(1.seconds)); // create 'updated' event in In queue
    e = cache.cacheEvents;
    assert(e.length == 1);
    assert(e.front.key == 4);
    assert(e.front.event == EventType.Updated);
    cache.put(3, 33); // create 'updated' event in Out queue
    e = cache.cacheEvents;
    assert(e.length == 1);
    assert(e.front.key == 3);
    assert(e.front.event == EventType.Updated);
    cache.put(2, 22); // create 'updated' event in In queue
    e = cache.cacheEvents;
    assert(e.length == 1);
    assert(e.front.key == 2);
    assert(e.front.event == EventType.Updated);
    Thread.sleep(1500.msecs);
    // In: 4, 5
    // Out: 3
    // Main: 2
    cache.put(6,6);     // now key '4' expired and must be dropped from In queue
    e = cache.cacheEvents;
    assert(e.length == 1);
    assert(e.front.key == 4);
    assert(e.front.event == EventType.Expired);
    // In: 5, 6
    // Out: 3
    // Main: 2
    cache.put(7, 7);
    // In: 6, 7
    // Out: 3, 5
    // Main: 2
    cache.put(8, 8);
    // In: 7, 8
    // Out: 5, 6 -> 3 evicted
    // Main: 2
    e = cache.cacheEvents;
    assert(e.length == 1);
    assert(e.front.key == 3);
    assert(e.front.event == EventType.Evicted);
    cache.remove(7); // remove from In
    cache.remove(5); // remove from Out
    cache.remove(2); // remove from main
    cache.remove(0); // remove something that were not in cache
    e = cache.cacheEvents;
    assert(e.length == 3);
    assert(e.all!(a => a.event == EventType.Removed));
    assert(e.map!"a.key".array == [7,5,2]);
}

///
///
///
unittest
{

    // create cache with total size 1024
    auto allocator = Mallocator.instance;
    auto cache = () @trusted {
        return allocator.make!(Cache2Q!(int, string))(1024);
    }();
    () @safe @nogc nothrow {
        cache.sizeIn = 10; // if you need, later you can set any size for In queue
        cache.sizeOut = 55; // and for out quque
        cache.sizeMain = 600; // and for main cache
        cache.put(1, "one");
        assert(cache.get(1) == "one"); // key 1 is in cache
        assert(cache.get(2).isNull); // key 2 not in cache
        assert(cache.length == 1); // # of elements in cache
        cache.clear; // clear cache
    }();
    dispose(allocator, cache);
}

// test unsafe types
unittest {
    import std.variant;
    import std.stdio;

    alias UnsafeType = Algebraic!(int, string);
    
    auto c = new Cache2Q!(UnsafeType, int);
    c.enableCacheEvents;

    UnsafeType abc = "abc";
    UnsafeType def = "abc";
    UnsafeType one = 1;
    c.put(abc, 1);
    c.put(one, 2);
    assert(abc == def);
    assert(c.get(def) == 1);
    assert(c.get(one) == 2);
    c.remove(abc);
    auto r = c.cacheEvents;
    c.sizeMain = 100;
    c.sizeIn = 100;
    c.sizeOut = 100;
    c.length;


    import std.json;
    auto csj = new Cache2Q!(string, JSONValue);
    auto cjs = new Cache2Q!(JSONValue, string);

    class C {
        // bool opEquals(const C other) {
        //     return other is this;
        // }
    }
    auto c1 = new Cache2Q!(C, string);
    auto cob1 = new C();
    auto cob2 = new C();
    c1.put(cob1, "cob1");
    c1.put(cob2, "cob2");
    assert(c1.get(cob1) == "cob1");
    assert(c1.get(cob2) == "cob2");
}