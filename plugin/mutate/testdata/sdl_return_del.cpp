/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

bool bool_f() { return false; }

void void_f() { return; }

void void_f2(int* x) {
    if (*x > 3)
        return;
    *x = 42;
}
