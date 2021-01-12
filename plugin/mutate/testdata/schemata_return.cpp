/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

bool fn(int argc) { return argc == 42; }

int main(int argc, char** argv) {
    int x = 42;
    x = x + argc;
    x = x + argc;
    x = x + argc;

    return fn(argc);
}
