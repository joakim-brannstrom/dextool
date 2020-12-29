/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2018
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#include <assert.h>

inline void aInlineFunc() {}

#if (__cplusplus >= 201103L)

constexpr bool isAConstExpr() { return true; }

#if !defined(GTEST_INTERNAL_DEPRECATED)

#if defined(_MSC_VER)
#define GTEST_INTERNAL_DEPRECATED(message) __declspec(deprecated(message))
#elif defined(__GNUC__)
#define GTEST_INTERNAL_DEPRECATED(message) __attribute__((deprecated(message)))
#else
#define GTEST_INTERNAL_DEPRECATED(message)
#endif

#endif // !defined(GTEST_INTERNAL_DEPRECATED)

GTEST_INTERNAL_DEPRECATED("INSTANTIATE_TEST_CASE_P is deprecated, please use "
                          "INSTANTIATE_TEST_SUITE_P")
constexpr bool InstantiateTestCase_P_IsDeprecated() { return true; }

#endif

class Bar {
public:
    Bar() {}
    ~Bar() {}
    virtual void foo() = 0;
};

class Foo : public Bar {
public:
    Foo() : Bar() {}
    ~Foo() {}
    void foo() override {}
};

int cover(int x) {
    if (x > 3) {
        return 0;
    }
    return 1;
}

int unused(int x) {
    if (x > 3) {
        return 0;
    }
    return 1;
}

int main(int argc, char** argv) {
    int r = cover(4);
    assert(r == 0);
    r = cover(1);
    assert(r == 1);
    return 0;
}
