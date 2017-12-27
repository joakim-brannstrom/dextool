/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

class OpOverload {
public:
    OpOverload();

    // AOR
    OpOverload operator+(const OpOverload&);
    OpOverload operator-(const OpOverload&);
    OpOverload operator*(const OpOverload&);
    OpOverload operator/(const OpOverload&);
    OpOverload operator%(const OpOverload&);

    OpOverload operator=(const OpOverload& o);
};

void arith_op_on_object() {
    OpOverload a, b, res;

    res = a + b;
    res = a - b;
    res = a * b;
    res = a / b;
    res = a % b;
}
