/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

void gun();
void wun(int);

void fun() {
    // expection the following to be deleted
    int x;
    x = 2;
    gun();

    // expecting this if-stmt to be deleted
    if (x > 3) {
        x = 4;    // delete until the ;
    }

    // expecting this if-stmt to be deleted
    if (x > 5) {
        // the content of this block shall be deleted
        x = 7;
    }

    // expecting this for stmt to be deleted
    for (int i = 0; i < 4; ++i) {
        // the content of this block shall be deleted
        wun(i);
    }
}

int stun(double y) {
    // this should NOT be deleted. it results in funky mutants that would
    // result in random data, in this case.
    return static_cast<int>(y);
}

void dun(double y) {
    // this return stmt should be deleted.
    return;
}
