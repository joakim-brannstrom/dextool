// Contains a C++ interface. Pure virtual.
// Expecting an implementation.

class Simple {
public:
    Simple() {}
    virtual ~Simple() {}

    // Test simple virtual function result in a generate.
    virtual int func1() = 0;

    // Test function overloading result in generated stubs that are
    // distinguised from each other.
    virtual void func2(int x) = 0;
    virtual void func2(double x) = 0;
    virtual void func2(double* x) = 0;

    // Test that name mangling avoids collisions.
    virtual void func3(long x, long y) = 0;
    virtual void func3(long long x) = 0;

    // Test operators result in opAssign etc.
    virtual void operator=(const Simple& other) = 0;
    // virtual void operator==(const Simple& other) = 0;
    // virtual void operator!=(const Simple& other) = 0;
    // virtual void operator<(const Simple& other) = 0;
    // virtual void operator<=(const Simple& other) = 0;
    // virtual void operator>(const Simple& other) = 0;
    // virtual void operator=>(const Simple& other) = 0;

private:
    // Test that even private functions are generated from an interface.
    virtual void func3() = 0;
};

/** Use case.
 * StubSimple stub;
 * stub.StubGet().func1().call_counter;
 */
