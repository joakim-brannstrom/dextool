/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

typedef float myFloat;
typedef double myDouble;

void relation_operators() {
    myFloat a = 1.0;
    myDouble b = 2.0;

    bool c = a < b;
    bool d = a <= b;
    bool e = a > b;
    bool f = a >= b;
    bool g = a == b;
    bool h = a != b;
}
