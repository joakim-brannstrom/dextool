/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#ifndef PRETTY_PRINT_HPP
#define PRETTY_PRINT_HPP

#include <vector>

typedef int myInt;

struct pod_two {
    int x;
};

typedef pod_two myPod;

struct pod_one {
    int int_;
    long long_;
    float float_;
    double double_;
    long double long_double_;
    char char_;

    myInt myInt_;
    myPod myPod_;
};

struct primitive_aggregate_types {
    bool bool_arr[2];
    int int_arr[2];
    double double_arr[2];
    char char_arr[2];
};

struct cpp_data_structure_types {
    std::vector<int> int_vec;
    std::vector<double> double_vec;
};

#endif // PRETTY_PRINT_HPP
