/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

int a_binary_unary_inside_if(int x) {
    int y = x;
    if (!x == 1) {
        y++;
    }
    if (x == 3) {
        y = 2;
    }
    if (x == 4) {
        y += 5;
    }
    return y;
}

int main(int argc, char** argv) { return 0; }
