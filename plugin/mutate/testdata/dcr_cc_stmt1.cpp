/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

bool isPredicateFunc(int x, int y) {
    bool a = x == 0;
    bool b = x == 1 || x == 2;
    bool c = y > 0 && x > 2;
    return a;
}
