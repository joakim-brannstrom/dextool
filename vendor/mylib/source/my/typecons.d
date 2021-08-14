/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module my.typecons;

/** Creates a copy c'tor for all members in the struct.
 *
 * This is only meant for structs where all members are to be copied. For anything more complex write a custom ctor.
 */
mixin template CopyCtor() {
    this(ref return scope typeof(this) rhs) @safe pure nothrow @nogc {
        import std.traits : FieldNameTuple;

        static foreach (Member; FieldNameTuple!(typeof(this))) {
            mixin(Member ~ " = rhs." ~ Member ~ ";");
        }
    }
}

@("shall create a copy constructor")
unittest {
    static struct A {
        int x;
        int y;

        mixin CopyCtor;
    }

    auto a = A(1, 2);
    auto b = a;
    assert(a == b);
}
