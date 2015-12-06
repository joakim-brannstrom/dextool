// Contains a C++ interface. Pure virtual.
// Expecting generation of a google mock implementation.

class Simple {
public:
    Simple() {}
    virtual ~Simple() {}

    virtual void func1() const = 0;
};
