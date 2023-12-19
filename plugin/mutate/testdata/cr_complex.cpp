/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#include "cr_complex.hpp"

void fun() {
    auto x = foo::x;
    x = 42;
    foo::Foo f;
    f.x = x;
    foo::Bar<int> g;
    g.y = f.x;
    g.x = foo::fun<int>(3);

    auto h = foo::Smurf::a;
}
