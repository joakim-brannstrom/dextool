/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
/// This file contains a couple of different structs and classes that a pretty
/// printer is expected/not expected to be generated for.
#ifndef TEST_PRETTY_PRINT_GENERATOR_HPP
#define TEST_PRETTY_PRINT_GENERATOR_HPP

struct pod_primitive_types {
    int int_;
    long long_;
    float float_;
    double double_;
    long double long_double_;
    char char_;
};

typedef pod_primitive_types myPod;
typedef int myInt;

struct pod_composed {
    myInt myInt_;
    myPod myPod_;
};

class InterfaceWithPubMember {
public:
    virtual ~InterfaceWithPubMember();
    virtual void f();

    int x;
};

// no pretty printer for this
struct pod_empty {
};

// no pretty printer for this
struct pod_only_private {
private:
    int x;
};

// no pretty printer for this
struct pod_only_protected {
protected:
    int x;
};

class InterfaceWithoutAnyPubMember {
public:
    virtual ~InterfaceWithoutAnyPubMember();
    virtual void f();
};

#endif // TEST_PRETTY_PRINT_GENERATOR_HPP
