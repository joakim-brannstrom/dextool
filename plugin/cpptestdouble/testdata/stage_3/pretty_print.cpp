/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#include "gtest/gtest.h"

#include "test_double_gmock.hpp"
#include <iostream>
#include <string>

struct TestCase {
    std::string name;
    TestCase(const char* n) : name(n) {
        std::cout << "begin: " << name << std::endl;
    }
    ~TestCase() { std::cout << "end: " << name << std::endl; }
};
#define begin() TestCase junk_instance_name(__FUNCTION__)

void test_calling_pretty_print() {
    begin();
    PrintTo(pod_one(), &std::cout);
    std::cout << std::endl;
}

void test_pretty_print_with_values() {
    begin();
    pod_one a = {1, 2, 3, 4, 5, 'a'};
    PrintTo(a, &std::cout);
    std::cout << std::endl;
}

void test_expect_eq() {
    begin();
    pod_one a = {1, 2, 3, 4, 5, 'a', 2, {2}};
    pod_one b = a;

    EXPECT_EQ(a, b);
    if (a == b)
        std::cout << "Equal check passed" << std::endl;

    b = a;
    b.int_ = 2;
    EXPECT_EQ(a, b);

    b = a;
    b.long_ = 1;
    EXPECT_EQ(a, b);

    b = a;
    b.float_ = 2;
    EXPECT_EQ(a, b);

    b = a;
    b.double_ = 2;
    EXPECT_EQ(a, b);

    b = a;
    b.long_double_ = 2;
    EXPECT_EQ(a, b);

    b = a;
    b.char_ = 'b';
    EXPECT_EQ(a, b);

    b = a;
    b.myInt_ = 1;
    EXPECT_EQ(a, b);

    b = a;
    b.myPod_ = {3};
    EXPECT_EQ(a, b);
}

void test_c_aggregate_eq() {
    begin();
    primitive_aggregate_types agg_a = {
        {true, false}, {1, 2}, {0, 0}, {'a', '\0'}};
    primitive_aggregate_types agg_b = agg_a;

    EXPECT_EQ(agg_a, agg_b);
    if (agg_a == agg_b)
        std::cout << "Equal check passed" << std::endl;

    // test field by field to ensure that one doesn't hide another
    agg_b = agg_a;
    agg_b.bool_arr[1] = true;
    EXPECT_EQ(agg_a, agg_b);

    agg_b = agg_a;
    agg_b.int_arr[1] = 3;
    EXPECT_EQ(agg_a, agg_b);

    agg_b = agg_a;
    agg_b.double_arr[1] = 3.5;
    EXPECT_EQ(agg_a, agg_b);

    agg_b = agg_a;
    agg_b.char_arr[0] = 'b';
    EXPECT_EQ(agg_a, agg_b);
}

int main(int argc, char** argv) {
    bool exit_status = true;

    test_calling_pretty_print();
    test_pretty_print_with_values();
    test_expect_eq();
    test_c_aggregate_eq();

    std::cout << (exit_status ? "Passed" : "Failed") << std::endl;

    return !exit_status;
}
