/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#include "dextool/dextool.hpp"

#include "transform_param.hpp"

FUZZ_TEST(Case, One) {
    // fuzz the parameter with the default data source.
    A param_input_for_fa;
    dextool::fuzz(param_input_for_fa);

    // check the data is validate. The API is, of course, not robust to fuzzed
    // data that it isn't designed to be able to handle.
    if (param_input_for_fa.x >= 1000 && param_input_for_fa.y >= 2000 && param_input_for_fa.z >= 3000) {
        return;
    }

    // call the API function with the fuzzed data.
    // If it crashes the fuzzer has found a bug.
    fa(param_input_for_fa);
}
