#ifndef STRUCTS_H
#define STRUCTS_H

struct Foo {
    int a;
};

typedef struct Bar {
    int x;
} b;

typedef struct Foo c;

struct A {
    struct B {
        int x;
    } b;
};

struct C {
    struct {
        int x;
        int y;
    } point;
};

typedef struct {
    int x;
    int y;
} D;

struct E;

struct E {
};

struct F;

#endif // STRUCTS_H
