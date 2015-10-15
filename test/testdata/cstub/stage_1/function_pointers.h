/* not extern, should not result in anything */
void (*a)(void);
int (*b)(void);
void (*c)(int);
int (*d)(int, int);
int (*e)(int a, int b);
int (*f)(int a, int b, ...);

/* same input but extern. Expecting them defined as variables. */
extern void (*a)(void);
extern int (*b)(void);
extern void (*c)(int);
extern int (*d)(int, int);
extern int (*e)(int a, int b);
extern int (*f)(int a, int b, ...);

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
