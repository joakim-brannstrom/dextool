/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#ifndef TEST_PRETTY_PRINT_IN_NS_CPP
#define TEST_PRETTY_PRINT_IN_NS_CPP

#include "test_double_gmock.hpp"

void test_using_gtest_expects() {
    ns1::A a = {1};
    ns1::A b = {2};

    EXPECT_EQ(a, a);
    EXPECT_EQ(a, b);
}

void test_using_from_nested_ns() {
    ns1::ns2::B a = {1};
    ns1::ns2::B b = {2};

    EXPECT_EQ(a, a);
    EXPECT_EQ(a, b);
}

int main(int argc, char** argv) {
    test_using_gtest_expects();
    test_using_from_nested_ns();

    return 0;
}

#endif // TEST_PRETTY_PRINT_IN_NS_CPP
