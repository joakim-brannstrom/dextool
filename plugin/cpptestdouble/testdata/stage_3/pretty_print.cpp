/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#include "gtest/gtest.h"

#include <iostream>
#include "test_double_gmock.hpp"

void test_calling_pretty_print() {
    PrintTo(pod_one(), &std::cout);
    std::cout << std::endl;
}

void test_pretty_print_with_values() {
    pod_one a = {1, 2, 3, 4, 5, 'a'};
    PrintTo(a, &std::cout);
    std::cout << std::endl;
}

void test_expect_eq() {
    pod_one a = {1, 2, 3, 4, 5, 'a'};
    pod_one b = {1, -2, 3, 4, 5, 'b'};

    EXPECT_EQ(a, b);
}

int main(int argc, char** argv) {
    test_calling_pretty_print();
    test_pretty_print_with_values();
    test_expect_eq();

    return 0;
}
