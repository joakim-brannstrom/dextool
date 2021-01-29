/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#include <array>

class ArraySub {
public:
    ArraySub() = default;
    ArraySub(const ArraySub& other) = delete;
    ArraySub(ArraySub&&) = default;
    ArraySub& operator=(const ArraySub& other) = delete;
    ArraySub& operator=(ArraySub&& other) noexcept = delete;
    ~ArraySub() = default;

    void fn1() { arr[2]; }
    void fn2() const { arr[2]; }
    constexpr int fn3() const { return arr[2]; }

    void fn4(int x, int y) { arr[x + y * x]; }
    void fn5(int x, int y) const { arr[x + y * x]; }
    constexpr int fn6(int x, int y) const { return arr[x + y * x]; }

private:
    int arr[42];
};

int main(int argc, char** argv) { return 0; }
