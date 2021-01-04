/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

bool isPredicateFunc(int x, int y) {
    if (x == 0) {
        return true;
    } else {
        return false;
    }

    if (x == 1 || x == 2) {
        return true;
    } else {
        return false;
    }

    if (y > 0 && x > 2) {
        return true;
    }

    return false;
}
