struct Struct_with_union {
    union {
        int x;
        char y;
    }
    nested_union;
};
