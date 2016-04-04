#ifndef ARRAYS_H
#define ARRAYS_H

#ifndef TEST_ARRAY
int intern_a[4];
#endif

extern int extern_a[4];
extern int extern_b[2][3];
extern int extern_c[2][3][4];

extern char extern_incmpl[];
extern const char* const extern_const_incmpl[];

extern int* const expect_const_ptr_array[10];
#endif // ARRAYS_H
