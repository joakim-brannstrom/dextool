/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

char* fn1() { return nullptr; }
bool fn2() { return true; }
bool fn3(int x) { return true; }

int main(int argc, char** argv) {
    if (char* x = fn1()) {
        argv[0] = nullptr;
    }
    if (bool x = fn3(42)) {
    }
    if (fn2()) {
    }

    return 0;
}
