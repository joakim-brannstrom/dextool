/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2019
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#include "impl.hpp"

bool compare(std::string lhs, std::string rhs) {
    bool is_same = lhs.size() == rhs.size();
    if (is_same) {
        for (size_t i = 0; i < lhs.size(); ++i) {
            is_same = lhs[i] == rhs[i];
        }
    }
    return is_same;
}
