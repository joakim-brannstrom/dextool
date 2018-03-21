/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

enum class MyE {
    A, B, C
};

void relation_operators() {
    MyE a = MyE::A;
    MyE b = MyE::C;

    bool g0 = a == b;
    bool g1 = MyE::A == b;
    bool g2 = MyE::B == b;
    bool g3 = a == MyE::C;
    bool g4 = a == MyE::A;
}
