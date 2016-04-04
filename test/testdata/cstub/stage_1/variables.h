// Prefixed with exect_ is expected to be found represented in the Symbol
// Container.
#ifndef VARIABLES_H
#define VARIABLES_H

// Test of primitive types
int a;
extern int expect_b;

/* a duplicate, expecting it to be ignored */
extern int expect_b;

// Test of constness
extern const int expect_c;

// Test of primitive pointers
extern int* expect_d;
extern int** expect_e;

// Test of pointer constness
extern const int* expect_f;
extern int* const expect_g;
extern const int* const expect_h;
extern const int* const* expect_i;

// Test of typedef primitive type
typedef int my_int;
extern my_int expect_my_int;
extern const my_int* const expect_const_my_int;

#endif // VARIABLES_H
