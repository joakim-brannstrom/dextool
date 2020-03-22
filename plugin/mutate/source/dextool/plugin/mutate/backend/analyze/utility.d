/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.analyze.utility;

struct Stack(T) {
    import std.typecons : Tuple;
    import automem;

    alias Element = Tuple!(T, "data", uint, "depth");
    Vector!(Element) stack;

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
        return stack[$ - 1].data;
    }

    bool empty() @safe pure nothrow const @nogc {
        return stack.empty;
    }
}
