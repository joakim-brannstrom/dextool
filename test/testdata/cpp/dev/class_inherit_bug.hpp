// the following code resulted in B having multiple "void a(bool)"
namespace barf {

namespace Interface {

class I1 {
public:
    virtual ~I1();

    virtual void a(bool) = 0;
};

} // NS: Interface

class A : public Interface::I1 {
public:
    A& operator=(const A& other);
    virtual ~A();

    virtual void a(bool);
};

class B : public A {
public:
    virtual ~B();

    virtual void a(bool);
};

} // NS: barf
