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

/// Description
class Class4 {
public:
    Class4() = default;
    Class4(const Class4& other) = default;
    Class4(Class4&&) = default;
    Class4& operator=(const Class4& other) = default;
    Class4& operator=(Class4&& other) noexcept = default;
    ~Class4() = default;

    void method1();
    void method2() const;
    void method3();

private:
    int x;
    Class4* child;
};

void Class4::method1() { x = 42; }

void Class4::method2() const { auto y = x + 42; }

void Class4::method3() {
    auto& x2 = x;

    while (x2 < 42) {
        x2++;

        if (child->x >= 42) {
            if (child->x == 43) {
                x2 += 4;
                break;
            }
            return;
        }
    }
}

int main(int argc, char** argv) {
    int x = 42;
    x = x + argc;
    x = x + argc;
    x = x + argc;
    x = x + argc;
    x = x + argc;

    return 0;
}
