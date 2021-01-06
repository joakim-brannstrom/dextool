/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#include <stdlib.h>

int main(int argc, char** argv) {
    void* p = malloc(42);
    p = malloc(42);
    p = malloc(42);
    p = malloc(42);
    return 0;
}
