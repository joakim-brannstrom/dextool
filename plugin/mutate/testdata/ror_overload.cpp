/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

class OpOverload {
public:
    OpOverload();

    // ROR
    bool operator>(const OpOverload&);
    bool operator>=(const OpOverload&);
    bool operator<(const OpOverload&);
    bool operator<=(const OpOverload&);
    bool operator==(const OpOverload&);
    bool operator!=(const OpOverload&);
};

void relation_operators() {
    OpOverload a, b;
    a < b;
    a <= b;
    a > b;
    a >= b;
    a == b;
    a != b;
}
