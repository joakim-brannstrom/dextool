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
namespace Inner {

typedef enum {
    Enum_0,
    Enum_1
} Enum;

typedef struct {
} Struct;

} // NS: Inner
} // NS: Scope

namespace ns_using_scope {
namespace ns_using_inner {

// function using types from Scope::Inner in the function signature
void enum_named_arg(Scope::Inner::Enum e0);
void enum_unnamed_arg(Scope::Inner::Enum);
void enum_ptr_arg(Scope::Inner::Enum* e0);
void enum_ref_arg(Scope::Inner::Enum& e0);
Scope::Inner::Enum enum_rval();
Scope::Inner::Enum* enum_ptr_rval();
Scope::Inner::Enum& enum_ref_rval();

void struct_one_named_arg(Scope::Inner::Struct e0);
void struct_unnamed_arg(Scope::Inner::Struct);
void struct_ptr_arg(Scope::Inner::Struct* e0);
void struct_ref_arg(Scope::Inner::Struct& e0);
Scope::Inner::Struct struct_rval();
Scope::Inner::Struct* struct_ptr_rval();
Scope::Inner::Struct& struct_ref_rval();

} // NS: ns_using_inner
} // NS: ns_using_scope
