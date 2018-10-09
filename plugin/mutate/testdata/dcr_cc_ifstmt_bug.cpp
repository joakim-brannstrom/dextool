/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2018
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
// bug: the DCR operator did not produce a true/false mutation for the
// predicate.

bool otherFun();

bool isPredicateFunc(int x, int y) {
    if (!otherFun())
        return x;
    return y;
}
