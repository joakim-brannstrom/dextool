// C declarations inside a C++ namespace.
// Expecting a test double interface inside the same namespace.

namespace ns {

void fun_cpp_linkage();

extern "C" {
#include "ns_c_linkage.h"
}

} // namespace ns

namespace level0 {

namespace level1 {

void fun_level1();

} // namespace level1

} // namespace level0
