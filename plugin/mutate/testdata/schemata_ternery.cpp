/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

void fn() {}

int main(int argc, char** argv) {
    char* x = argc > 2 ? *argv : argc > 42 ? argv[2] : 0;
    int y = argc > 2    ? static_cast<int>(**argv) - 42
            : argc > 42 ? 42 + static_cast<int>(*argv[2]) + 3
                        : 0;
    argc > 2 ? fn() : fn();

    return 0;
}
