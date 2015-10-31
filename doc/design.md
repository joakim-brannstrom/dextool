# Assumption
Templates aren't allowed to be used. Coding standard, embedded systems etc.

From the different test doubles it is a stub we generate. But just following the definition will produce something that isn't very useful.

The generator cannot know what complex behaviour the tester need so it allows the tester to register callbacks to user implemented functions where the tester have full control.

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
