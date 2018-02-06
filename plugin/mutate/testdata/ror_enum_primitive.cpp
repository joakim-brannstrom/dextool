/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

enum class MyE {
    A, B, C
};

void relation_operators() {
    MyE a = MyE::A;
    MyE b = MyE::C;

    bool c = a < b;
    bool d = a <= b;
    bool e = a > b;
    bool f = a >= b;
    bool g = a == b;
    bool h = a != b;
}
