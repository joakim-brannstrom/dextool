/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Based on require in `object.d` in druntime therefor the Boost license.

A convenient function extending cachetools with a common recurring function.
*/
module dextool.cachetools;

import dextool.from;

/***********************************
 * Looks up key; if it exists returns corresponding value else evaluates
 * value, adds it to the associative array and returns it.
 * Params:
 *      aa =     The cache.
 *      key =    The key.
 *      value =  The required value.
 * Returns:
 *      The value.
 *
 * Example:
 * ---
 * auto cache = CacheLRU!(int,string);
 * cache.require(5, { return "5"; }());
 * ---
 */
V require(CT, K, V)(CT aa, K key, lazy V value = V.init)
        if (is(CT == from.cachetools.CacheLRU!(K, V))) {
    auto q = aa.get(key);
    if (q.isNull) {
        auto v = value;
        aa.put(key, v);
        return v;
    }
    return q.get;
}
