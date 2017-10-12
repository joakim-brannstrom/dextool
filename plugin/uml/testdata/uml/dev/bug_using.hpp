namespace ns1 {

class A {
};

} // NS: ns1

namespace ns2 {

// Expecting nothing in the class diagram.
using ::ns1::A;

} // NS: ns2

namespace ns3 {

// Expecting a typeref from B in ns3 to B in ns1.
// The concrete record is in ns1
using A = ::ns1::A;

// Expecting a relation from C -> ns1::B via the typeref.
class B : public A {
};

} // NS: ns3

namespace ns4 {

using namespace ns1;

class C : public A {
};

} // NS: ns4
