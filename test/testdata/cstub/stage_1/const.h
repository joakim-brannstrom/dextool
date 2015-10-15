extern const int a; // const int
extern const int* b; // mutable pointer to const int
extern int* const c; // const pointer to mutable int
extern const int* const d; // const pointer to const int
extern const int* const* e;  // mutable pointer to const pointer to const int
extern const int* const* const f;  // const pointer to const pointer to const int
extern int* const* const g;  // const pointer to const pointer to mutable int

typedef struct Foo {
    int a;
    int b;
    int c;
} Foo;

extern const Foo bar;
