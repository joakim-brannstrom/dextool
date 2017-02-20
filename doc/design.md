# OLD NOTES
For pre v0.1.
Not applicable for the current design (0.7+).
Kept for when a stub-generator that is simpled and independent from google mock is introduced.

# Assumption
Templates aren't allowed to be used. Coding standard, embedded systems etc.

From the different test doubles it is a stub we generate. But just following the definition will produce something that isn't very useful.

The generator cannot know what complex behavior the tester need so it allows the tester to register callbacks to user implemented functions where the tester have full control.

The normal case is "hardcoded" values that can be set by the tester during runtime.

The tester can also access the last value sent to the functions via parameters.

Therefor the following deviations are made:
 - Spy ability for if the method was called (boolean).
 - Spy ability for parameters sent to the stub's methods.
 - Runtime configuration of return values from member methods.
 - Register callbacks for member methods.

# Thoughts about design
Allow callback on any function in runtime.

Must store the data somewhere.
In a namespace? Test?

Must allow custom copy functions.
How?
How does google mock do it?
Yes, all the parameter magic hmm.
This is hard
I think the easiest is that the user can supply a hdr-file that implements copy functions.

const CAN affect direction of data of parameters. Assume that?

## Stored and used data
call counter.
parameters in/out.

### Proposal
Prefix must affect namespace and structs.
Prefix must be able to be controlled by user.
Store in a namespace Internal.
const references are stored as pointers.

name mangling:
typerval funcname(type1 param1)
in struct for stub data mangled to:
(call counter) -> unsigned funcname_cnt;
(callback) -> Ifuncname\* funcname_callback;
typerval -> typerval funcname_return;
param1 -> type1 funcname_params_param1;

Example of interface:
```cpp
class Simple {
public:
    Simple();
    virtual ~Simple();

    virtual void func1() = 0;
    virtual void operator=(const Simple& other) = 0;

private:
    virtual char* func3() = 0;
};
```

Example of generated stub code:
```cpp
namespace StubCallbackSimple {
struct IctorSimple { virtual void ctorSimple() = 0; };
struct IdtorSimple { virtual void dtorSimple() = 0; };
struct Ifunc1 { virtual void func1() = 0; };
struct Iop_assign { virtual void op_assign(const Simple& other) = 0; };
struct Ifunc3 { virtual char* func3() = 0; };

class StubCompleteInterface : public IctorSimple,
    public IdtorSimple,
    public Ifunc1,
    public Iop_assign,
    public Ifunc3 {
};
} //NS: StubSimpleCallback

namespace StubInternalSimple {
struct StubData {
    unsigned ctor_Simple_cnt;
    StubSimpleCallback::IctorSimple* ctor_Simple_callback;

    unsigned dtor_Simple_cnt;
    StubSimpleCallback::IdtorSimple* dtor_Simple_callback;

    unsigned func1_cnt;
    StubSimpleCallback::Ifunc1* func1_callback;

    unsigned op_assign_cnt;
    Simple* op_assign_params_other;
    StubSimpleCallback::Iop_assign* op_assign_callback;

    unsigned func3_cnt;
    char* func3_return;
};
} //NS: StubInternalSimple
```

# Architecture

The suffix Context is used for structs that visit the AST with clangs visitor.

# Global initialization (ctestdouble)
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

