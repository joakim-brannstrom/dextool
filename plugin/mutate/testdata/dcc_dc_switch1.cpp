/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2020
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

// clang-format off
// contains small formatting "errors". This is intentional to test that the
// offsets are calculated correctly.
int isPredicateFunc(int x) {
    switch (x) {
    case 0:
        return -1 ;
    case 1:
        return 1;
    case 3:
        break;
    case 4:
    case 2:{
            return 100;
        }
    default:
        return 0;
    }

    return 42;
}
