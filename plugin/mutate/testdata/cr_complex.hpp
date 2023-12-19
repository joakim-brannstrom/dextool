/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

namespace foo {
int x{40};

struct Foo {
    int x{3};
    int y{2};
};

template <typename T> struct Bar {
    int x{3};
    T y{4};
};

template <typename T> int fun(T x) {
    x = x + 1;
    return x;
}

enum class Smurf {
    // should not be mutated
    a = 1,
    b = 2
};

} // namespace foo
