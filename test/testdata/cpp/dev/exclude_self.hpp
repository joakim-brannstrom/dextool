// C declarations inside a C++ namespace.
// Expecting a test double interface inside the same namespace.
#include "a_ns_with_func.hpp"

namespace ns {

void exclude_self();

class Foo {
public:
};

} // NS: ns
