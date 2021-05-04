/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

void renderOcean() {
    auto mod = [](int x, int m) {
        if (x >= 0)
            return x % m;
        else
            return m - 1 - (-x % m);
    };
}

struct TestCase {};

template <int&... ExplicitParameterBarrier, typename Factory>
void RegisterTest(void*, Factory factory) {
    TestCase* a = factory();
}

void fun(int x) {
    RegisterTest(nullptr, [x] {
        int y;
        y = x;
        return new TestCase();
    });
}

int main(int argc, char** argv) { return 0; }
