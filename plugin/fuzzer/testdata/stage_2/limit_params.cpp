/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#include "limit_params.hpp"

static void test_failed() {
    *((char*) 0) = 'x';
}

bool s[10];

void nolimit(int v) {
    if (v > 1000) {
        s[0] = true;
    }
}

void upper_limit(int v) {
    if (v > 1000) {
        test_failed();
    }

    if (v < -200000) {
        s[7] = true;
    }
}

void lower_limit(int v) {
    if (v < 1000) {
        test_failed();
    }

    if (v > 100000) {
        s[8] = true;
    }
}

void band_limit(int v) {
    if (v < 2000 || v > 4000) {
        test_failed();
    }

    if (v > 3000) {
        s[9] = true;
    }
}
