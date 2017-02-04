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

# Global initialization
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

1.
Make a C++ interface that is used to initialize the global variables.
Make each global a pure method.
    It forces the user to update the class implementing the interface when a
    new global has been added.

2.
The adapter for the test double takes as reference a class that implement the
interface.
It forces the user to implement "initializers" of the globals.
Make a conscious decision.
The adapter then calls the functions in its constructor.
It sends "events" to the global initializer.

3.
Make the interface just a plain, void methods. No arguments.
It simplifies the implementation of the C++ interface.
Less boiler plate.
Makes it easier to implement because there are cases, especially C++, where it
is "hard" to know how to pass the object.
Leave as much as possible to the implementor.

A side effect of the design is that it is easy for the user to "ignore"
initializing globals if so is desired.

4. (EXTRA)
The global initializer from the user is NOT passed by reference.
It is to make it possible for the user to call the adapter without first having
to create an instance in the scope;

## Example
// software under test
extern int a;

// test double code
namespace TestDouble {
class I_InitGlobals {
public:
    virtual void a() = 0;
};

class Adapter {
public:
    Adapter(I_InitGlobals init_globals) {
        init_globals.a();
    }
};
} //NS: TestDouble


