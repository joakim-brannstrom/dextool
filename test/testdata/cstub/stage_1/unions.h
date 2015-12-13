union Foo {
    int a;
};

typedef union Bar {
    int x;
} b;

typedef union Foo c;

union A {
    union B {
        int x;
    } b;
};

union C {
    union {
        int x;
        int y;
    } point;
};

typedef union {
    int x;
    int y;
} D;
