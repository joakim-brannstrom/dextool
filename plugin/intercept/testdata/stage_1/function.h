#ifndef FUNCTIONS_H
#define FUNCTIONS_H
// this file contains constructs that fully or partially need to be inspected
// by checking the generated source code.

// expect defined without ... even though it is variadic according to C.
void func_variadic();

// expect a variadic function one enumerated parameter and variadic ...
int func_variadic_one_unnamed(char*, ...);

// expect no different behavior for an extern function
extern int func_extern(int out);

// expect enumeration of unnamed parameters
void unnamed_params(int, int);

// expect a func signature exactly as the function below.
// Not uncommon in C code that the keyword struct is used.
void c_func_with_struct(const struct A* a);

// expecting static functions to be ignored
static void ignore();

#endif // FUNCTIONS_H
