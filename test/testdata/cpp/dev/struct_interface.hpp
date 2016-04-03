#ifndef STRUCT_INTERFACE_HPP
#define STRUCT_INTERFACE_HPP

// Even though this isn't common in C++ code it needs to be handled

struct Struct {
    virtual ~Struct();

    virtual void func();
};

#endif // STRUCT_INTERFACE_HPP
