#ifndef FUNCTIONS_H
#define FUNCTIONS_H
// Expecting definitions for all function declarations.
// A class with pure virtual member functions for each C function.

namespace ns {

// expect plain, simple function definitions.
void func_void(void);
int func_return(void);
int func_one_named(int a);
void func_two_named(int a, int b);
void func_three_named(int a, int b, int c);

const int c_func_return(void);
const int c_func_one_named(const int a);
void c_func_two_named(const int a, const int b);
void c_func_three_named(const int a, const int b, const int c);

// expect defined without ... even though it is variadic according to C.
void func_variadic();

// expect a variadic function one enumerated parameter and variadic ...
int func_variadic_one_unnamed(char*, ...);

// expect no different behavior for an extern function
extern int func_extern(int out);

// expect enumeration of unnamed parameters
void unnamed_params(int, int);

// expect usage of the typedef and NOT the underlying types
typedef int (*func_ptr2)(int, int);
typedef struct Something_Big {
    int tiny;
} Something_Big;
extern void fun(func_ptr2 p, Something_Big b);

// expect a correct call signature for a function ptr
void func_ptr_arg(int (*a)(int p, int), int b);

// C++ behaves different from C.
// In C++ the struct keyword is not expected to be kept in the function
// signature, compared to C where it is.
void c_func_with_struct(const struct A* a);

// C++ testing
void func_ref(int& a);
int& func_return_ref();
void func_ref_many(int& a, char& b);
void func_array(int a[10]);
void func_ref_ptr(int*& a);
void func_ref_array(int (&a)[10]);

} // NS: ns
#endif // FUNCTIONS_H
