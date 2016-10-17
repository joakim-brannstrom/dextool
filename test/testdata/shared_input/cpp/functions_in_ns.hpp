namespace ns {

#include "functions.h"

// C++ testing
void func_ref(int& a);
int& func_return_ref();
void func_ref_many(int& a, char& b);
void func_array(int a[10]);
void func_ref_ptr(int*& a);
void func_ref_array(int (&a)[10]);

} // NS: ns

// Test that an implicitly named enum/struct is correctly represented in the
// function signature.
// This is only a problem for C++ code.
namespace Scope {

typedef enum {
    Enum_0,
    Enum_1
} Enum;

typedef struct {
} Struct;

} // NS: Scope

namespace ns_using_scope {

// function using types from Scope in the function signature
void enum_named_arg(Scope::Enum e0);
void enum_unnamed_arg(Scope::Enum);
void enum_ptr_arg(Scope::Enum* e0);
void enum_ref_arg(Scope::Enum& e0);
Scope::Enum enum_rval();
Scope::Enum* enum_ptr_rval();
Scope::Enum& enum_ref_rval();

void struct_one_named_arg(Scope::Struct e0);
void struct_unnamed_arg(Scope::Struct);
void struct_ptr_arg(Scope::Struct* e0);
void struct_ref_arg(Scope::Struct& e0);
Scope::Struct struct_rval();
Scope::Struct* struct_ptr_rval();
Scope::Struct& struct_ref_rval();

} // NS: ns_using_scope
