/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

class Foo {
public:
    Foo() { x = 42; }
    template <typename Type> Foo(Type x) { x = 42; }
    ~Foo() = default;
    int x;
};

template <typename Type> class Foo2 {
public:
    Foo2() { x = 42; }
    Foo2(Type x) { x = 42; }
    ~Foo2() = default;
    int x;
};

int main(int argc, char** argv) { return 0; }
