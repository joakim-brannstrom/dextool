/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

namespace foo {
bool a;
bool b;
} // namespace foo

void logical_operators() {
    bool a = true;
    bool b = false;

    if (a || b)
        return;
    if (a && b)
        return;
    if (a and b)
        return;
    if (a or b)
        return;
    // if the below line is moved from line 22 then the test needs to be updated.
    if (foo::a || foo::b)
        return;
}
