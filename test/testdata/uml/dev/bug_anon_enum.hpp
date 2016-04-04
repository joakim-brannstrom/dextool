struct Struct_with_anon_enum {
    enum {
        ENUM_X,
    } Enum;
};

struct Foo {
    int s0 = Struct_with_anon_enum::ENUM_X;
};

struct Struct_with_typedef_anon_enum {
    typedef enum {
        ENUM_Y,
    } Enum;
};

struct Bar {
    Struct_with_typedef_anon_enum::Enum s1;
};

typedef Struct_with_typedef_anon_enum A;
typedef A B;
typedef const B C;

struct Struct_using_via_typedef {
    // thus expecting a relation to Struct_with_anon_enum
    // BUG somehow the AST is empty
    B a;
};
