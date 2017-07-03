/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#include "transform_param.hpp"

static void test_failed() {
    *((char*) 0) = 'x';
}

bool s[10];

void fa(A a) {
    if (a.x > 1000) {
        test_failed();
    }

    if (a.y > 2000) {
        test_failed();
    }

    if (a.z > 3000) {
        test_failed();
    }

    if (a.x == 99 && a.x == a.y) {
        s[0] = true;
    }
}
