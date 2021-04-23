/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#include <string>

template <typename T> void aTemplate(T x) { T y = x + "foo"; }

int main(int argc, char** argv) {
    aTemplate(std::string{"a"});
    aTemplate(std::string{"a"} + std::string{"b"});
    return 0;
}
