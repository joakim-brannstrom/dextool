/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
/// This file contains test data that purpusefully have different parameter
/// names between the interface class and the one inheriting from it.
#ifndef BUG_CLASS_INHERIT_HPP
#define BUG_CLASS_INHERIT_HPP

/// Description
class Interface {
public:
    virtual ~Interface() {}

    virtual int a_method(int x) = 0;

};

class Derived : public Interface {
public:
    virtual ~Derived() {}

    virtual int a_method(int x_value) {
        return 42;
    }
};

#endif // BUG_CLASS_INHERIT_HPP
