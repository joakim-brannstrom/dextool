/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

class OpOverload {
public:
    OpOverload();

    // AOR
    int operator+(const OpOverload&);
    int operator-(const OpOverload&);
    int operator*(const OpOverload&);
    int operator/(const OpOverload&);
};

void arithemtic_operators() {
    int a = 1;
    int b = 2;

    int c = a + b;
    int d = a - b;
    int e = a * b;
    int f = a / b;

    OpOverload oa, ob;
    oa + ob;
    oa - ob;
    oa* ob;
    oa / ob;
}
