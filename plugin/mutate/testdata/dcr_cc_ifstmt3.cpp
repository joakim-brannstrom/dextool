/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

int main(int argc, char** argv) {
    int x{42};

    if (int start_digits = argc > 100)
        x = 43;
    if (int start_digits = argc > 5)
        x = 43;
    if (argc == 5 || argc == 7)
        x = 43;
    if (argc == 42 || argc == 3)
        x = 44;

    return x == 42 ? 0 : 1;
}
