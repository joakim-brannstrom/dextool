/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

enum class MyE {
    A, B, C
};

void relation_operators() {
    MyE a = MyE::A;
    MyE b = MyE::C;

    bool h0 = a != b;
    bool h1 = MyE::A != b;
    bool h2 = MyE::B != b;
    bool h3 = MyE::C != b;
    bool h4 = a != MyE::A;
    bool h5 = a != MyE::B;
    bool h6 = a != MyE::C;
}
