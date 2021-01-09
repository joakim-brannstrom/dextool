/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.analyze.utility;

import dextool.plugin.mutate.backend.analyze.ast : Interval;

enum Direction {
    bottomToTop,
    topToBottom,
}

struct Stack(T) {
    import std.typecons : Tuple;
    import my.container.vector;

    alias Element = Tuple!(T, "data", uint, "depth");
    Vector!Element stack;

    alias stack this;

    // trusted: as long as arr do not escape the instance
    void put(T a, uint depth) @trusted {
        stack.put(Element(a, depth));
    }

    // trusted: as long as arr do not escape the instance
    void pop() @trusted {
        stack.popBack;
    }

    /**
     * It is important that it removes up to and including the specified depth
     * because the stack is used when doing depth first search. Each call to
     * popUntil is expected to remove a layer. New nodes are then added to the
     * parent which is the first one from the previous layer.
     *
     * Returns: the removed elements.
     */
    auto popUntil(uint depth) @trusted {
        Vector!T rval;
        while (!stack.empty && stack[$ - 1].depth >= depth) {
            rval.put(stack[$ - 1].data);
            stack.popBack;
        }
        return rval;
    }

    T back() {
        return stack.back.data;
    }

    bool empty() @safe pure nothrow const @nogc {
        return stack.empty;
    }

    /** The depth of the parent that is furthest away or in other words closest
     * to zero.
     *
     * Returns: the depth (1+) if any of the parent nodes is `k`, zero
     * otherwise.
     */
    uint isParent(K)(K k) {
        return match!((a) {
            if (a[0].data == k)
                return a[0].depth;
            return 0;
        })(stack, Direction.bottomToTop);
    }
}

/** Run until `pred` returns something that evaluates to true, in that case
 * return the value.
 *
 * `pred` should take one parameter.
 */
auto match(alias pred, T)(ref T stack, Direction d) {
    auto rval = typeof(pred(stack[0 .. $])).init;

    if (stack.empty)
        return rval;

    auto safeSlice(size_t i) @trusted {
        return stack[i .. $];
    }

    final switch (d) {
    case Direction.bottomToTop:
        foreach (i; 0 .. stack.length) {
            rval = pred(safeSlice(i));
            if (rval)
                break;
        }
        break;
    case Direction.topToBottom:
        for (long i = stack.length - 1; i > 0; --i) {
        }
        foreach (i; 0 .. stack.length) {
            rval = pred(safeSlice(i));
            if (rval)
                break;
        }
        break;
    }

    return rval;
}

/** An index that can be queries to see if an interval overlap any of those
 * that are in it. Create an index of all intervals that then can be queried to
 * see if a Cursor or Interval overlap a macro.
 */
struct Index(KeyT) {
    Interval[][KeyT] index;

    this(Interval[][KeyT] index) {
        this.index = index;
    }

    void put(KeyT k, Interval i) {
        if (auto v = k in index) {
            (*v) ~= i;
        } else {
            index[k] = [i];
        }
    }

    /// Check if `i` overlap any intervals for `key`.
    bool overlap(const KeyT key, const Interval i) {
        if (auto intervals = key in index) {
            foreach (a; *intervals) {
                if (a.intersect(i))
                    return true;
            }
        }

        return false;
    }
}
