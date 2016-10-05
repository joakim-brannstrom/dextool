#include <stdio.h>

#ifdef TEST_INCLUDE
#include "test_double.hpp"

#ifdef TEST_CONST
#define TEST_INIT_a const int a = 3
#define TEST_INIT_c int* const c = reinterpret_cast<int*>(7)
#define TEST_INIT_d const int* const d = reinterpret_cast<int*>(7)
#define TEST_INIT_f const int* const* const f = reinterpret_cast<const int* const* const>(7)
#define TEST_INIT_g int* const* const g = reinterpret_cast<int *const *const>(7)
#define TEST_INIT_bar const Foo bar = {0,1,2}
#define TEST_INIT_extern_array const int extern_array[3] = {0,1,2}
#define TEST_INIT_extern_const_typedef_array const MyIntType extern_const_typedef_array[2] = {0,1}
#endif

#ifdef TEST_FUNC_PTR
#define TEST_INIT_e_d void (* const e_d)() = 0
#define TEST_INIT_hest func_ptr hest = 0
#endif

#ifdef TEST_ARRAY
#define TEST_INIT_extern_incmpl char extern_incmpl[1]
#define TEST_INIT_extern_const_incmpl const char* const extern_const_incmpl[] = {0, 0}
#define TEST_INIT_expect_const_ptr_array int* const expect_const_ptr_array[10] = {0,0,0,0,0,0,0,0,0,0}
#endif

#ifdef TEST_FUNC
#define TEST_INIT_djurpark const djur_type djurpark[3] = {HEST, HEST, HEST}
#endif

#include "test_double_global.cpp"
#endif

int main(int argc, char** argv) {
    printf("stub ok\n");
    return 0;
}
