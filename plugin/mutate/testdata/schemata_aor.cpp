/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#include <cstdint>
#include <cstdlib>
#include <cstring>

template <bool ok = true, typename T>
inline bool find(const T* first, const T* last, T value, const T*& out) {
    return ok;
}

template <>
inline bool find<false, char>(const char* first, const char* last, char value, const char*& out) {
    out = static_cast<const char*>(
        std::memchr(first, value, static_cast<std::uint64_t>(last - first)));
    return out != nullptr;
}

struct Struct1 {
    enum { buffer_size = 3 };

    mutable char buffer_[buffer_size];
    char* str_;

    size_t size() const { return static_cast<std::size_t>(buffer_ - str_ + buffer_size - 1); }
};

int main(int argc, char** argv) { return 0; }
