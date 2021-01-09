/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2020
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

// clang-format off
// contains small formatting "errors". This is intentional to test that the
// offsets are calculated correctly.
bool isPredicateFunc(int x) {
    switch (x) {
    case 0:
        return false ;
    case 1:
        return true;
    case 3:
        break;
    case 4:
    case 2:{
            return false;
        }
    default:
        return false;
    }

    return true;
}
