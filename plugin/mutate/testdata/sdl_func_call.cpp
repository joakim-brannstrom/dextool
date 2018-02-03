/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2018
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

void gun();
void wun(int);
int calc(int);

int fun() {
    gun();
    wun(5);
    wun(calc(6));
    if (calc(7) == calc(8))
        return 9;
    return calc(10) + calc(11);
}
