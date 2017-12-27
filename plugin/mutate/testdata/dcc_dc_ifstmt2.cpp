/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

bool isPredicateFunc(int x, int y) {
    if (x) {
        if (y)
            return true;
        return false;
    } else {
        return false;
    }
}
