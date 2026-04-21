/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#include <ranges>
#include <vector>

int main(int argc, char** argv) {
    std::vector<int> numbers = {1, 2, 3, 4};
    auto even = numbers | std::views::filter([](int n) { return n % 2 == 0; }) |
                std::views::filter([](int n) { return n % 2 == 0; });

    // just a silly mutant so a schema is generated
    int x = argc == 42 || argc == 43;

    return 0;
}
