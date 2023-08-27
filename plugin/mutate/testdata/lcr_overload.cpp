/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

class OpOverload {
public:
    OpOverload();

    // LCR
    bool operator&&(const OpOverload&);
    bool operator||(const OpOverload&);
};

namespace foo {
OpOverload a;
OpOverload b;
} // namespace foo

void logical_operators() {
    OpOverload a, b;
    bool res;

    res = a || b;
    res = a && b;

    res = a and b;
    res = a or b;

    // if the below line is moved from line 29 then the test needs to be updated.
    res = foo::a || foo::b;
}
