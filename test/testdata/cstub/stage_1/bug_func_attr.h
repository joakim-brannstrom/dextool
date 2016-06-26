// An attribute is the first child node.
// Interfers when finding the TypeRef node of a TypeDefDecl.

typedef int* yellow_ptr;
typedef yellow_ptr* berry_ptr;
typedef void(more_func_type)(const int x, const int* y, const berry_ptr z);
typedef more_func_type* yet_another_func_ptr;
typedef yet_another_func_ptr* other_func_ptr;
typedef void (func_type)(const int x, const char* z, const other_func_ptr w);

#define _STRANGER_ __attribute__ ((section(".ram.text")))

extern func_type this_is_wrong _STRANGER_;
