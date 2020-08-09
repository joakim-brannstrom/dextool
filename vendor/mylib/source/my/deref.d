/**
Copyright: Copyright (c) 2020, Meta. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Meta (https://forum.dlang.org/post/fshlmahxfaeqtwjbjouz@forum.dlang.org)
*/
module my.deref;

/**
 * A safe-dereferencing wrapper resembling a Maybe monad.
 *
 * If the wrapped object is null, any further member dereferences will simply
 * return a wrapper around the .init value of the member's type. Since non-null
 * member dereferences will also return a wrapped value, any null value in the
 * middle of a chain of nested dereferences will simply cause the final result
 * to default to the .init value of the final member's type.
 *
 */
template SafeDeref(T) {
    static if (is(T U == SafeDeref!V, V)) {
        // Merge SafeDeref!(SafeDeref!X) into just SafeDeref!X.
        alias SafeDeref = U;
    } else {
        struct SafeDeref {
            T t;

            // Make the wrapper as transparent as possible.
            alias t this;

            // This is the magic that makes it all work.
            auto opDispatch(string field)()
                    if (is(typeof(__traits(getMember, t, field)))) {
                alias Memb = typeof(__traits(getMember, t, field));

                // If T is comparable with null, then we do a null check.
                // Otherwise, we just dereference the member since it's
                // guaranteed to be safe of null dereferences.
                //
                // N.B.: we always return a wrapped type in case the return
                // type contains further nullable fields.
                static if (is(typeof(t is null))) {
                    return safeDeref((t is null) ? Memb.init : __traits(getMember, t, field));
                } else {
                    return safeDeref(__traits(getMember, t, field));
                }
            }
        }
    }
}

/**
 * Wraps an object in a safe dereferencing wrapper resembling a Maybe monad.
 *
 * If the object is null, then any further member dereferences will just return
 * a wrapper around the .init value of the wrapped type, instead of
 * dereferencing null. This applies recursively to any element in a chain of
 * dereferences.
 *
 * Params: t = data to wrap.
 * Returns: A wrapper around the given type, with "safe" member dereference
 * semantics.
 */
auto safeDeref(T)(T t) {
    return SafeDeref!T(t);
}

unittest {
    class Node {
        int val;
        Node left, right;

        this(int _val, Node _left = null, Node _right = null) {
            val = _val;
            left = _left;
            right = _right;
        }
    }

    auto tree = new Node(1, new Node(2), new Node(3, null, new Node(4)));

    import std.stdio;

    writeln(safeDeref(tree).right.right.val);
    writeln(safeDeref(tree).left.right.left.right);
    writeln(safeDeref(tree).left.right.left.right.val);
}

// Static test of monadic composition of SafeDeref.
unittest {
    {
        struct Test {
        }

        alias A = SafeDeref!Test;
        alias B = SafeDeref!A;

        static assert(is(B == SafeDeref!Test));
        static assert(is(SafeDeref!B == SafeDeref!Test));
    }

    // Timon Gehr's original test case
    {
        class C {
            auto foo = safeDeref(C.init);
        }

        C c = new C;

        //import std.stdio;
        //writeln(safeDeref(c).foo); // SafeDeref(SafeDeref(null))

        import std.string;

        auto type = "%s".format(safeDeref(c).foo);
        assert(type == "SafeDeref!(C)(null)");
    }
}
