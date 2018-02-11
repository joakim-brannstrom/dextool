/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

int* a0();
int* a1();

int* b0();
int* b1();

int* c0();

int* d0();

void relation_operators() {
    bool a2 = a0() == a1();

    bool b2 = b0() != b1();

    bool c1 = c0() == 0;

    bool d1 = d0() != 0;
}
