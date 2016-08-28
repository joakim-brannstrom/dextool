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
