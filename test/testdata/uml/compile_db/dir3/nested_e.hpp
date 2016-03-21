// should NOT result in duplicated symbols when merging
#include "nested_c.hpp"
#include "nested_d.hpp"

class A;

namespace ns1 {

class E1 {};

namespace ns12 {

class E12 {};

} // NS: ns11

namespace ns11 {

class E11 {};

class E11Inherit : public E1, protected ns12::E12, private ns11::C11 {};

} // NS: ns11

} // NS: ns1
