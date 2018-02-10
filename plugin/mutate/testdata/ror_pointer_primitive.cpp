/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

void relation_operators() {
    int* a0, *a1;
    bool a2 = a0 == a1;

    int* b0, *b1;
    bool b2 = b0 != b1;

    int* c0;
    bool c1 = c0 == 0;

    int* d0;
    bool d1 = d0 != 0;

    // normal still works
    int e0, e1;
    bool e2 = e0 == e1;

    // normal still works
    int f0, f1;
    bool f2 = f0 != f1;
}
