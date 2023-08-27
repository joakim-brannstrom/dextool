/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

namespace foo {
bool a;
bool b;
} // namespace foo

void logical_operators() {
    bool a = true;
    bool b = false;

    bool c = a || b;
    bool d = a && b;

    bool e = a and b;
    bool f = a or b;

    // if the below line is moved from line 20 then the test needs to be updated.
    bool h = foo::a || foo::b;
}
