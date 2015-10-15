#include <stdio.h>

#ifdef TEST_INCLUDE
#include "test_double.hpp"
#include "test_double_global.cpp"
#endif

int main(int argc, char** argv) {
    printf("stub ok\n");
    return 0;
}
