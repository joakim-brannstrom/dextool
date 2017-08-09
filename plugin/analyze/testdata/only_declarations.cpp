void f();

class A;

class B {
    void m();
};

namespace  {

void g();

} // NS:

namespace ns {

void gun();

} // NS: ns

class A {
public:
    A() = default;
    A(const A& other) = delete;
    A& operator=(const A& other) = delete;
    virtual ~A();

private:
};
