/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

namespace bar {
int x = 42;
float a = 2.0;
double z = 3.0;

void fn() {
    auto y = x;
    auto yy = a;
    auto yyy = z;

    auto v = 28.0;
    const auto l = 23.0;

    auto w = 55;
    const auto a = 88;
}
} // namespace bar
