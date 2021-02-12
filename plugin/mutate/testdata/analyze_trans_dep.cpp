/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#include "program.hpp"

#ifdef IS_VERSION_TWO

void foo() {
    int x = 42;
    x = x + 2;
    x = x + 2;
    x = x + 2;
    x = x + 2;
    x = x + 2;
    x = x + 2;
    x = x + 2;
}

#else

void foo() {}

#endif
