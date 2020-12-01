/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2020
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

int fn(int x);

int test_switch(int x) {
    switch (x) {
    case 0:
        return 2;
    case 1: {
        return 3;
    }
    case 5:
        fn(2);
        fn(3);
        fn(4);
        break;

    case 6: {
        fn(2);
        fn(3);
        fn(4);
        break;
    }

    // fallthrough had a bug wherein dcc crashed
    case 2:
    case 3:
    default:
        x = 42;
        break;
    }

    return x;
}
