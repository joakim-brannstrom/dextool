/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#include <vector>

template <typename T> void swap(T&, T&);
template <typename T> bool operator<(const T& lhs, const T& rhs);

struct X {
    // bool operator<(const X &other) { return true; }
};
void swap(X&, X&) {}
bool operator<(const X& lhs, const X& rhs) { return true; }

template <typename T> void reverse(T* first, T* last) {
    while (*first < *last) {
        swap(*first, *--last);
        ++first;
    }
}

struct Y {
    // bool operator<(const Y &other) { return true; }
};
void swap(Y&, Y&) {}
bool operator<(const Y& lhs, const Y& rhs) { return true; }

int main(int argc, char** argv) {
    X v[10];
    reverse(&v[0], &v[9]);

    return 0;
}
