#ifndef FUNCTION_POINTERS_H
#define FUNCTION_POINTERS_H

/* not extern, should not result in anything */
#ifndef TEST_FUNC_PTR
void (*a)(void);
int (*b)(void);
void (*c)(int);
int (*d)(int, int);
int (*e)(int pa, int pb);
int (*f)(int pa, int pb, ...);
#endif

/* same input but extern. Expecting them defined as variables. */
extern void (*e_a)(void);
extern int (*e_b)(void);
extern void (*e_c)(int);
extern void (*const e_d)(void);
extern int (*e_e)(int, int);
extern int (*e_f)(int pa, int pb);
extern int (*e_g)(int pa, int pb, ...);

/* subtle difference between a function prototype that is reused via a typedef
 * and a function pointer.
 *
 * Expecting func_type to result in a function definition and affect the interface.
 * Expecting func_ptr to be defined as a variable.
 */
typedef unsigned char (func_type)(const unsigned int baz);
typedef unsigned char (*func_ptr)(const unsigned baz);
typedef func_type under_type;

extern func_ptr hest;
extern func_type tiger;
extern under_type cyber;
#endif // FUNCTION_POINTERS_H
