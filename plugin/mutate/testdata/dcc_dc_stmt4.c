/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
// Test mutation of C code using different kind of bools

#include <stdbool.h>

bool isPredicateFunc(int x, int y) {
    bool r = x == 0 || y == 0;
    return r;
}

int isPredicateFunc2(int x, int y) {
    int r = x == 0 || y == 0;
    return r;
}

#define FALSE 0
#define TRUE !(FALSE)

int isPredicateFunc3(int x) {
    int r = x == TRUE;
    return r;
}
