namespace ns1 {

class A {
};

class B {
};

} // NS: ns1

namespace ns2 {

using ::ns1::A;

// node not handled
using B = ::ns1::B;

class C : public B {
};

} // NS: ns2
