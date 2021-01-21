/**
Copyright: Copyright (c) 2021, Atila Neves. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Atila Neves

Custom versions of std.experimental.allocator functions (unfortunately)
*/
module my.alloc.dispose_;

/**

Destroys and then deallocates (using $(D alloc)) the object pointed to by a
pointer, the class object referred to by a $(D class) or $(D interface)
reference, or an entire array. It is assumed the respective entities had been
allocated with the same allocator.

*/
void dispose(A, T)(auto ref A alloc, T* p) {
    import std.traits : hasElaborateDestructor;

    static if (hasElaborateDestructor!T) {
        () @trusted { .destroy(*p); }();
    }
    alloc.deallocate((cast(void*) p)[0 .. T.sizeof]);
}

/// Ditto
void dispose(A, T)(auto ref A alloc, T p) if (is(T == class) || is(T == interface)) {

    if (!p)
        return;
    static if (is(T == interface)) {
        version (Windows) {
            import core.sys.windows.unknwn : IUnknown;

            static assert(!is(T : IUnknown),
                    "COM interfaces can't be destroyed in " ~ __PRETTY_FUNCTION__);
        }
        auto ob = cast(Object) p;
    } else
        alias ob = p;
    auto support = (cast(void*) ob)[0 .. typeid(ob).initializer.length];

    () @trusted { .destroy(p); }();

    alloc.deallocate(support);
}
