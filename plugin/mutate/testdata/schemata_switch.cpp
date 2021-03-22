/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#include <string>

void log(int x, const std::string& message) {}
void log(int x, const std::string& message, int y) {}

void log2(int x) {}

void bar(int x) {
    std::string m;
    switch (x) {
    case 0:
        log(42, m + "foo");
        log(42, m + "foo");
        break;
    case 1:
    case 2:
    case 3:
        break;
    default:
        break;
    }

    log2(42);
    log2(42);
    log2(42);
}

int main(int argc, char** argv) { return 0; }
