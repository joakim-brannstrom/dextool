#include <stdio.h>

#ifdef TEST_INCLUDE
#include "test_double.hpp"

#ifdef TEST_CONST
#define TEST_INIT_a a = 3
#define TEST_INIT_c c = reinterpret_cast<int*>(7)
#define TEST_INIT_d d = reinterpret_cast<int*>(7)
#define TEST_INIT_f f = reinterpret_cast<const int* const* const>(7)
#define TEST_INIT_g g = reinterpret_cast<int *const *const>(7)
#define TEST_INIT_bar bar = {0,1,2}
#endif

#ifdef TEST_FUNC_PTR
#define TEST_INIT_e_d = 0
#define TEST_INIT_hest hest = 0
#endif

#include "test_double_global.cpp"
#endif

int main(int argc, char** argv) {
    printf("stub ok\n");
    return 0;
}
