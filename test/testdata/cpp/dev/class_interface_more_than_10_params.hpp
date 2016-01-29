// Contains a C++ interface. Pure virtual.
// Expecting generation of a google mock implementation.
// Important: the other files are practically empty.

class Simple {
public:
    Simple() {}
    virtual ~Simple() {}

    // Test that methods with 10 parameters are generated correctly.
    virtual void func10(int x1, int x2, int x3, int x4, int x5, int x6, int x7, int x8, int x9, int x10) = 0;

    // Test that methods with 11 parameters are generated correctly.
    virtual int func11(int x1, int x2, int x3, int x4, int x5, int x6, int x7, int x8, int x9, int x10,
                       int x11) = 0;

    // Test that void methods with 11 parameters are generated correctly.
    virtual void vfunc11(int x1, int x2, int x3, int x4, int x5, int x6, int x7, int x8, int x9, int x10,
                         int x11) = 0;

    // Test that methods with 30 parameters are generated correctly.
    virtual int func30(int  x1, int  x2, int  x3, int  x4, int  x5, int  x6, int  x7, int  x8, int  x9, int x10,
                       int x11, int x12, int x13, int x14, int x15, int x16, int x17, int x18, int x19, int x20,
                       int x21, int x22, int x23, int x24, int x25, int x26, int x27, int x28, int x29, int x30) = 0;

    // Test that const methods with 12 parameters are generated correctly.
    virtual int const_func12(int x1, int x2, int x3, int x4, int x5, int x6, int x7, int x8, int x9, int x10,
                             int x11, int x12) const = 0;
};
