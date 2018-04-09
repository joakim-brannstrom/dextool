/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2018
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

const char* to_be_mutated(int var1_long_text, int var2_long_text) {
    // important that the expression >5 characters
    if (var1_long_text >5)
        return "false";

    switch (var2_long_text) {
    case 2:
        return "true";
    default:
        break;
    }

    return "false";
}
