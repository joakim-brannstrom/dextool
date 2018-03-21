/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

enum class MyE {
    A, B, C
};

void relation_operators() {
    MyE a = MyE::A;
    MyE b = MyE::C;

    bool c0 = a < MyE::C;
    bool c1 = MyE::C < b;

    bool e0 = a > MyE::C;
    bool e1 = MyE::C > b;

    bool d0 = a <= MyE::C;
    bool d1 = MyE::C <= b;

    bool f0 = a >= MyE::C;
    bool f1 = MyE::C >= b;

    bool h0 = a != b;
    bool h1 = MyE::A != b;
    bool h2 = MyE::B != b;
    bool h3 = a != MyE::C;
    bool h4 = a != MyE::A;
}
