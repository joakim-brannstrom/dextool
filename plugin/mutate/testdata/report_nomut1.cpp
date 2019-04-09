/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2018
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#include "report_nomut1.hpp"

const char* to_be_mutated(int var1_long_text, int var2_long_text) {
    if (var1_long_text > 5) /// NOMUT (not supported)
        return "false";     /** NOMUT (not supported) */

    switch (var2_long_text) { // NOMUT
    case 2:                   /* NOMUT */
        return "true";
    default: // NOMUT
        break;
    }

    // the important is that NOMUT is on the last line. That has been a problem because it is
    // "missed".
    gun("fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo"
        "oooooooooooooo",
        "barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr"
        "rrr",
        "bun"); // NOMUT (group1)

    Wun wun;
    wun.major(
        "fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo"
        "oooooooooooooo",
        "barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr"
        "rrr",
        "bun"); // NOMUT (group1) with comment

    return "false"; //       NOMUT
}
