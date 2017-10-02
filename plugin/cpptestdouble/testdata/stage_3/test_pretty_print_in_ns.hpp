/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#ifndef TEST_PRETTY_PRINT_IN_NS_HPP
#define TEST_PRETTY_PRINT_IN_NS_HPP

namespace ns1 {

struct A {
    int x;
};

namespace ns2 {

struct B {
    int y;
};


} // NS: ns2

} // NS: ns1

#endif // TEST_PRETTY_PRINT_IN_NS_HPP
