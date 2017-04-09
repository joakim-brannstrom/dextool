# Global initialization (ctestdouble)
This chapter describe the design of the global variable initializer for the
ctestdouble plugin.

Problem:
 - The user has raised the design problem that the tests become coupled when
   the globals aren't initialized before the test start.

Questions:
 1. How should an interface be designed to "notify" the user during compile
    time that a new global variable have been found that need to be
    initialized.
 2. How should the design ensure "correct by construction"?
 3. What information needs to be exposed in the interface?
    What can be hidden?
 4. How can it be made easy to use?

1. Make a C++ interface that is used to initialize the global variables.
Make each global a pure method.
    It forces the user to update the class implementing the interface when a
    new global has been added.

2. The adapter have two constructors (in the case of globals and free functions).
One that takes a ref to a class that implement I_TestDouble.
    Emulate what the compiler do to e.g. the .bss-segment.
    Namely blast zeroes over everything.
One that takes a ref to I_TestDouble and I_TestDouble_InitGlobals
    Allows the user to control how the initialization is performed.
    For the use case when the user want to initialize a global to something
    else besides zero.

3. Make the interface just a plain, void methods. No arguments.
It simplifies the implementation of the C++ interface.
Less boiler plate.
Makes it easier to implement because there are cases, especially C++, where it
is "hard" to know how to pass the object.
Leave as much as possible to the implementor.

side effect, the design is that it is easy for the user to "ignore"
initializing globals if so is desired.
Side effect, I_TestDouble_InitGlobals only change when the variable name
changes.

4. What is easy to use?
A definition is that the test double (with globals) behave as expected.
Both uninitialized (maybe crash) and initialized.

The most common case for globals is to initialize them to zero.
By providing an implementation of I_TestDouble_InitGlobals that do just that,
zero all globlas, it become easy to start using the test double for those cases
where zeroing is the correct behavior.

## Example
```cpp
// software under test
void fun();
extern int a;

// test double code
namespace {
    I_TestDouble* test_double_inst = 0;
}

namespace TestDouble {
class I_TestDouble {
public:
    virtual void fun() = 0;
};

class I_TestDouble_InitGlobals {
public:
    virtual void a() = 0;
};

class Test_ZeroGlobals : public I_TestDouble_InitGlobals {
public:
    virtual void a() { ::a = 0; }
}

class Adapter {
public:
    Adapter(I_TestDouble inst) {
        test_double_inst = &inst;
        Test_ZeroGlobals init_globals;
        init_globals.a();
    }

    Adapter(I_TestDouble inst, I_InitGlobals init_globals) {
        test_double_inst = &inst;
        init_globals.a();
    }
};
} //NS: TestDouble
```
