/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

enum class X : char { a = 1, b = 2 };

bool fn(X x) { return static_cast<char>(x) != 0; }

int main(int argc, char** argv) { return 0; }
