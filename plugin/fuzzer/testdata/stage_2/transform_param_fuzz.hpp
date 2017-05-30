/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#ifndef TRANSFORM_PARAM_FUZZ_HPP
#define TRANSFORM_PARAM_FUZZ_HPP

#include "transform_param.hpp"
#include "dextool/fuzz_helper.hpp"

struct fuzz_A {
    A param0;
    bool is_valid;

    fuzz_A() {
        dextool::fuzz(param0);

        if (param0.x < 1000 && param0.y < 2000 && param0.z < 3000) {
            is_valid = true;
        }
    }
};

#endif // TRANSFORM_PARAM_FUZZ_HPP
