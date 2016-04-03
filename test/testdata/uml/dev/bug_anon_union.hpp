// Buggy namespace backtrack of an anonymous union.
// For now it should be ignored.
// In the future it shall be handled as yet another relation.

struct Struct_with_union {
    union {
        int x;
    }
    nested_union;
};

struct Foo {
    Struct_with_union s;
};
