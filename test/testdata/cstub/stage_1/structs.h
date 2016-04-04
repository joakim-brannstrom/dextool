#ifndef STRUCTS_H
#define STRUCTS_H

struct Foo {
    int a;
};

typedef struct expect_Struct_typedef {
    int x;
} expect_Struct_typedef;

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

struct expect_Struct_in_struct_namespace {
};

struct {
} expect_Struct_anonymous_instance;

typedef struct {
} expect_anon_typedef_struct;

typedef struct expect_Struct_normal {
    // expect in Symbol container
    struct {
    } expect_Struct_nest_anonymous_instance;

    // expect to NOT be in symbol container, it just refers to a type in struct
    // namespace
    struct expect_Struct_in_struct_namespace inst_of_struct_in_ns;

    // expect to NOT be in symbol container
    expect_Struct_typedef inst_of_typedef;
} expect_Struct_normal;

typedef struct expect_Struct_nested_outer {
    struct expect_Struct_nested_inner {
        int x;
    };
} expect_Struct_nested_outer;

// Test of struct pointers
extern expect_Struct_typedef* expect_Struct_ptr;

struct Struct_with_union {
    union {
        int x;
        char y;
    } expect_anon_nested_union;

    // anonymous union
    union {
        int anon_x;
        char anon_y;
    };
};

#endif // STRUCTS_H
