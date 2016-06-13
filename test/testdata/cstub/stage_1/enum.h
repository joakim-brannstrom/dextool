#ifndef ENUM_H
#define ENUM_H
enum {
    expect_free_enum
};

enum {
    X_Enum_anon_inst
} expect_Enum_anon_inst;

void how_to_use_the_anon_inst() {
    expect_Enum_anon_inst = X_Enum_anon_inst;
}

typedef enum {
    X_anon_typedef_enum
} expect_anon_typedef_enum;

typedef enum expect_typedef_enum {
    X_typedef_enum
} expect_typedef_enum;

enum expect_Enum {
    X_enum
};
#endif // ENUM_H
