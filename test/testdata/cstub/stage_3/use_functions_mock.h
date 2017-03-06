#ifndef FUNCTIONS_H
#define FUNCTIONS_H
// Expecting definitions for all function declarations.
// A class with pure virtual member functions for each C function.

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
void func_ptr_arg(int (*a)(int p, int) , int b);

// expecting a func_return_func_ptr in the generated test double.
// (bug) Previously it derived the function signature from the return value.
typedef void (gun_type)(int);
typedef gun_type* gun_ptr;
gun_ptr func_return_func_ptr();

// using a typedef signature to create a function
extern gun_type gun_func;

// expecting the array parameter to be preserved
void array_func(int x, int* y, int z[16]);

typedef unsigned int MyIntType;
void array_func_param_typedef(MyIntType [16]);

// Bug (solved). The order is important.
// That the constant is defined and using the type before the functions.
// expect correct arguments even though an extern constant exist using the same type as a parameter.
typedef enum {HEST, ANKA} djur_type;
extern const djur_type djurpark[3];
void func_exhibit_type_bug_variant1(const djur_type a);
djur_type func_exhibit_type_bug_variant2(void);

// expect a func signature using the typedef'ed name in global namespace.
void func_with_enum_param(const djur_type a);
djur_type func_with_enum_param_and_return(const djur_type a);

#endif // FUNCTIONS_H
