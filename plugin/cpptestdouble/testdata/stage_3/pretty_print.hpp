/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#ifndef PRETTY_PRINT_HPP
#define PRETTY_PRINT_HPP

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

#endif // PRETTY_PRINT_HPP
