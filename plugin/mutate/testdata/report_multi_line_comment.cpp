/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2019
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

bool f() { return true; }

/* a multiline
 * comment
 * that should be rendered as
 * multiple lines in the html
 * report
 */
int fun(int x) {
    if (x > 3) {
        return 0;
    }
    return 1;
}
