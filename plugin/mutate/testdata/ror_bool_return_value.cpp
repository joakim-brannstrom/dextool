/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

bool a0();
bool a1();

bool b0();
bool b1();

void relation_operators() {
    bool a2 = a0() == a1();

    bool b2 = b0() != b1();
}
