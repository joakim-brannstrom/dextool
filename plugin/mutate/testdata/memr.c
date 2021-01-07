/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#include <stdlib.h>

void* xmalloc(size_t s) { return NULL; }
void* kmalloc(size_t s) { return NULL; }

int main(int argc, char** argv) {
    void* p = malloc(42);
    p = xmalloc(42);
    p = kmalloc(42);
    p = malloc(42);
    return 0;
}
