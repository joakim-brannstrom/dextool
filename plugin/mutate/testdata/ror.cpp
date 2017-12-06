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
    int a = 1;
    int b = 2;

    bool c = a < b;
    bool d = a <= b;
    bool e = a > b;
    bool f = a >= b;
    bool g = a == b;
    bool h = a != b;

    OpOverload oa, ob;
    oa < ob;
    oa <= ob;
    oa > ob;
    oa >= ob;
    oa == ob;
    oa != ob;
}
