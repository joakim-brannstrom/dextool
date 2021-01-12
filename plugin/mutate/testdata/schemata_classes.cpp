/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

/// the default keyword is used.
class Class1 {
public:
    Class1() = default;
    Class1(const Class1& other) = default;
    Class1(Class1&&) = default;
    Class1& operator=(const Class1& other) = default;
    Class1& operator=(Class1&& other) noexcept = default;
    virtual ~Class1() = default;
};

/// a virtual interface
class Class2 {
public:
    Class2() = default;
    Class2(const Class2& other) = default;
    Class2(Class2&&) = default;
    Class2& operator=(const Class2& other) = default;
    Class2& operator=(Class2&& other) noexcept = default;
    virtual ~Class2() = default;

    virtual int foo() = 0;
};

/// the delete keyword is used
class Class3 {
public:
    Class3() = default;
    Class3(const Class3& other) = delete;
    Class3(Class3&&) = default;
    Class3& operator=(const Class3& other) = delete;
    Class3& operator=(Class3&& other) noexcept = delete;
    virtual ~Class3() = default;
};

int main(int argc, char** argv) {
    int x = 42;
    x = x + argc;
    x = x + argc;
    x = x + argc;
    x = x + argc;
    x = x + argc;

    return 0;
}
