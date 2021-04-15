/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

constexpr bool kind1() { return true; }

#define GTEST_INTERNAL_DEPRECATED(message)

GTEST_INTERNAL_DEPRECATED("INSTANTIATE_TYPED_TEST_CASE_P is deprecated, please use "
                          "INSTANTIATE_TYPED_TEST_SUITE_P")
constexpr bool kind2() { return true; }

class Foo {
    int x;
    constexpr Foo(int a, int b) : x{a | b} {}

    constexpr int high() const { return x + x; }
};

int main(int argc, char** argv) {
    int x = 42;
    x = argc;
    x = argc;
    x = argc;
    x = argc;

    return 0;
}
