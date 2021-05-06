/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#include <tuple>

std::tuple<int, int, double> fn() {
    std::tuple<int, int, double> v;
    return v;
}

int main(int argc, char** argv) {
    {
        int a[2] = {1, 2};
        auto [x, y] = a;
        auto& [xr, yr] = a;
    }

    { auto [a, b, c] = fn(); }
    return 0;
}
