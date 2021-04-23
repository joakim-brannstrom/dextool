/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#include <string.h>

enum class X : char { a = 1, b = 2 };

static const char kPathSeparator = '/';
static const char kAlternatePathSeparator = '\\';

bool fn(X x) { return static_cast<char>(x) != 0; }
const char* c_str() { return nullptr; }

const char* findLastPathSeparator() {
    const char* const last_sep = strrchr(c_str(), kPathSeparator);
    const char* const last_alt_sep = strrchr(c_str(), kAlternatePathSeparator);
    // Comparing two pointers of which only one is NULL is undefined.
    if (last_alt_sep != nullptr && (last_sep == nullptr || last_alt_sep > last_sep)) {
        return last_alt_sep;
    }

    if (last_sep) {
        return nullptr;
    }

    return last_sep;
}

int main(int argc, char** argv) { return 0; }
