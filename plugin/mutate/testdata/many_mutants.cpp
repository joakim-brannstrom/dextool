/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
//
// some test cases just need a file with many mutants in it because they check
// the report, admin etc.

int main(int argc, char** argv) {
    int x = argc;
    if (argc == 1)
        x = 42;
    if (argc == 2)
        x = 43;
    if (argc == 3)
        x = 44;
    if (argc == 4)
        x = 45;
    if (argc == 5)
        x = 46;

    return x % 2;
}
