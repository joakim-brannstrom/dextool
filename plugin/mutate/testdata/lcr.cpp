/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

class OpOverload {
public:
    OpOverload();

    // LCR
    bool operator&&(const OpOverload&);
    bool operator||(const OpOverload&);
};

void logical_operators() {
    bool a = true;
    bool b = false;

    bool c = a || b;
    bool d = a && b;

    OpOverload oa, ob;
    oa || ob;
    oa&& ob;
}
