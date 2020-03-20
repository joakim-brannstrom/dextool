/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2018
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

class Fun {};
class Bun {};

int fun() {
    throw Fun();
    return 0;
}

void bun() {
    throw Bun();
    return;
}
