/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

class ArraySub {
public:
    ArraySub() {}
    ~ArraySub() {}

    void fn1() { arr[2]; }
    void fn2() const { arr[2]; }
    int fn3() const { return arr[2]; }

    void fn4(int x, int y) { arr[x + y * x]; }
    void fn5(int x, int y) const { arr[x + y * x]; }
    int fn6(int x, int y) const { return arr[x + y * x]; }

private:
    int arr[42];
};

/// a virtual interface
class Class2 {
public:
    virtual ~Class2() {}

    virtual int foo() = 0;
};

class Class4 {
public:
    Class4() {}
    ~Class4() {}

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
