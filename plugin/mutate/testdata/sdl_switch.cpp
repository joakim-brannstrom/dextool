/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2020
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

int fn(int x) { return x; }

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

namespace MyEnum {
enum Enum { passed, failed };
}

int test_switch2(MyEnum::Enum x) {
    int rval = 0;

    switch (x) {
    case MyEnum::Enum::passed:
        rval = 0;
        break;
    case MyEnum::Enum::failed:
        rval = 1;
        break;
    default:
        break;
    }

    return rval;
}

int main(int argc, char** argv) { return 0; }
