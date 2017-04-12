# (ctestdouble) Initialization of Global Variables
This chapter describe the design of the global variable initializer for the
ctestdouble plugin.

The feature described herein is to make it easier to design decoupled tests
from the start. It is a common problem that global variables create a hidden
coupling between tests. By assuring that they are reset between tests it makes
it _easier_ to find these couplings.

The Zero initializer is to make it easier for the test developer to initialize
global variables of type POD. The most common default initialization is namely
that, zero. To emulate what the compiler do with the .bss-segment.

The user in the following text is a Test Developer.

Problem:
 - The user has raised the problem that tests may become coupled when the
   global variables aren't initialized between tests.

Assumption:
 - The user is in all cases aware and responsible for the values in the global
   variables. If the SUT do use any of the global variables it is to be treaded
   with the same diligence as any other input. Explicit and mind aware. No
   excuse to be sloppy.

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
    Namely blast zeros over everything.
    This is achieved by using ZeroGlobals.

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

Side effect, the design is that it is easy for the user to "ignore"
initializing globals if so is desired.
Side effect, I_TestDouble_InitGlobals only change when the variable name
changes. The type is thus NOT encoded in the interface. Good/bad? Feedback
appreciated.

4. What is easy to use?
A definition is that the test double (with globals) behave as expected.
Both uninitialized (maybe crash) and initialized.

The most common case for globals is to initialize them to zero.
By providing an implementation of I_TestDouble_InitGlobals that do just that,
zero all global variables, it become easy to start using the test double for
those cases where zeroing is the correct behavior.

ZeroGlobals implementation.
    After consulting the user a ZeroGlobals implementation was added to ease
    the life and ensure a _good_ default behavior. Good behavior, no coupling
    between tests.

## Example

This is a condensed example of how the implementation can/should look like to
realize all the design points described above.

```cpp
// system under test
void fun();
extern int a;

// test_double (.hpp)
namespace TestDouble {
class I_TestDouble {
public:
    virtual void fun() = 0;
};

class I_TestDouble_InitGlobals {
public:
    // Explicit method for each global variable

    virtual void a() = 0;
};

class TestDouble_ZeroGlobals : public I_TestDouble_InitGlobals {
public:
    virtual void a();
};

class Adapter {
public:
    Adapter(I_TestDouble &inst);
    Adapter(I_TestDouble &inst, I_InitGlobals &init_globals);
};

// test_double (.cpp)
namespace {
    I_TestDouble* test_double_inst = 0;
}

void ZeroGlobals::a() {
    ::a = 0;
}

Adapter::Adapter(I_TestDouble &inst) {
    test_double_inst = &inst;
    Test_ZeroGlobals init_globals;
    init_globals.a();
}

Adapter::Adapter(I_TestDouble &inst, I_InitGlobals &init_globals) {
    test_double_inst = &inst;
    init_globals.a();
}
```
