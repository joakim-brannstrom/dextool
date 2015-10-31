/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2015
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
///TODO add chained inheritens

class Foo {
public:
    virtual void func2() {}
    virtual void func3() {}
};

namespace BarSpace {
class Bar {
public:
    virtual void func5() {}
};
}

class Warp : public Foo {
private:
    virtual void func4() = 0;
};

/// Description
class Smurf : public Foo, private BarSpace::Bar, public Warp
{
public:
    Smurf() {}
    virtual ~Smurf() {}
};

class DaddySmurf : public Warp {
public:
    DaddySmurf() {}
    virtual ~DaddySmurf() {}

    virtual void func2() = 0;
};
