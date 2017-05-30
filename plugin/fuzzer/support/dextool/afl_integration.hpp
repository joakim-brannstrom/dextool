/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
/// This file contains functionality for interoperability with AFL and libFuzzer.
#ifndef AFL_INTEGRATION_HPP
#define AFL_INTEGRATION_HPP

namespace dextool {

/// Main loop integrating and running fuzzy tests.
int afl_main(int argc, char** argv, dextool::DefaultSource** stdin_src);

} // NS: dextool

#endif // AFL_INTEGRATION_HPP
