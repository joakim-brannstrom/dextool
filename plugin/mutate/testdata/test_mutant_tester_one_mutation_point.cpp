/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2018
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

int fun(int x) {
    if (x) {
        return 0;
    }
    return 1;
}

int main(int argc, char** argv) {
    return fun(argc + 3);
}
