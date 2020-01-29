/**

 Set implemented as hash table

 Inherits @nogc and @safe properties from key properties.

 Implements next set ops
  $(UL create - fill set from range)
  $(UL add - add item to set; O(1))
  $(UL remove - remove item from set if present; O(1))
  $(UL length - number of items in set; O(1))
  $(UL join - join sets; O(N))
  $(UL intersection - create intersection of two sets; O(N))
  $(UL difference - create difference of two sets; O(N))
  $(UL iterate - create iterator over set items;)
  $(UL in - if element presented in set; O(1))
*/
module cachetools.containers.set;

import std.algorithm;
import std.range;

import cachetools.containers.hashmap;

///
/// create set from input range
///
auto set(R)(R r) if (isInputRange!R) {
    alias K = ElementType!R;
    Set!K result;
    r.each!(k => result.add(k));
    return result;
}

/// Set structure
struct Set(K) {
private:
        HashMap!(K, bool) _map;

public:

    /// Fill set from range
    void create(R)(R range) {
        _map.clear;
        range.each!(k => _map.put(k, true));
    }
    /// add element to set
    void add(K)(K k) {
        _map.put(k, true);
    }
    /// remove element from set
    void remove(K)(K k) {
        _map.remove(k);
    }
    /// number of items in set
    auto length() const {
        return _map.length;
    }
    /// join other set to this set
    void join(K)(Set!K other) {
        if ( other.length == 0 ) return;

        foreach(ref b; other._map._buckets.bs) {
            if ( b.hash >= ALLOCATED_HASH ) 
                _map.put(b.key, true);
        }
    }
    /// create intersection of two sets
    auto intersection(K)(Set!K other) {
        Set!K result;

        if (other.length == 0 || this.length == 0 ) return result;

        if ( other.length < _map.length ) {
            foreach (ref bucket; other._map._buckets.bs) {
                if ( bucket.hash >= ALLOCATED_HASH && bucket.key in _map )
                    result.add(bucket.key);
            }
        } else {
            foreach (ref bucket; _map._buckets.bs) {
                if (bucket.hash >= ALLOCATED_HASH && bucket.key in other._map)
                    result.add(bucket.key);
            }
        }
        return result;
    }
    /// create difference of two sets
    auto difference(K)(Set!K other) {
        Set!K result;
        if ( other.length == 0 ) return this;
        foreach (ref bucket; _map._buckets.bs) {
            if (bucket.hash >= ALLOCATED_HASH && bucket.key !in other._map)
                result.add(bucket.key);
        }
        return result;
    }
    /// iterate over items
    auto iterate() {
        return _map.byKey;
    }
    /// if element present in set
    bool opBinaryRight(string op)(K k) inout if (op=="in") {
        return  k in _map?true:false;
    }
}

///
@safe @nogc unittest {
    import std.stdio;

    Set!string s;
    s.add("hello");
    assert(s.length == 1);
    assert(equal(s.iterate, only("hello")));
    s.remove("hello");
    assert(s.length == 0);
    s.remove("hello");
    assert(s.length == 0);

    s.create(only("hello", "hello", "world"));
    assert(s.length == 2);

    s.join(set(only("and", "bye")));
    assert(s.length == 4);

    auto other = set(only("and", "bye", "!"));
    auto cross0 = s.intersection(other);
    assert("bye" in cross0);
    assert("!"  !in cross0);
    auto cross1 = other.intersection(s);
    assert(cross0.length == cross1.length);
    assert("and" in cross0 && "and" in cross1);
    assert("bye" in cross0 && "bye" in cross1);

    auto nums = set(iota(10));
    auto someNums = nums.difference(set(only(1,2,3)));
    assert(0 in someNums);
    assert(1 !in someNums);

    bool f(const Set!string s) {
        return "yes" in s;
    }

    Set!string ss;
    ss.add("yes");
    f(ss);
    assert("yes" in ss);
}