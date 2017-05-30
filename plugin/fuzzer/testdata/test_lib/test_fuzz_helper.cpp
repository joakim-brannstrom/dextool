/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
#include "dextool/dextool.hpp"

#include <assert.h>
#include <stdint.h>
#include <iostream>

FUZZ_TEST_S(fuzz_helper, Test_fuzz, 1) {
    std::cout << "Test: " << __PRETTY_FUNCTION__ << "\n";

    // Arrange
    int8_t i8 = 0;
    bool i8_ok = false;
    int16_t i16 = 0;
    bool i16_ok = false;
    int32_t i32 = 0;
    bool i32_ok = false;
    int64_t i64 = 0;
    bool i64_ok = false;

    // Act
    for (int32_t i = 0; i < INT32_MAX; ++i) {
        dextool::fuzz(i8);
        dextool::fuzz(i16);
        dextool::fuzz(i32);
        dextool::fuzz(i64);

        // sunny day test that the random generator behavior kinda the same
        // independent of the type.
        if (i8 > 0) {
            i8_ok = true;
        }
        if (i16 < 0) {
            i16_ok = true;
        }
        if (i32 > 0) {
            i32_ok = true;
        }
        if (i64 < 0) {
            i64_ok = true;
        }

        if (i8_ok && i16_ok && i32_ok && i64_ok) {
            return;
        }
    }

    // the test failed. Unable to generate positive/negative numbers
    assert(0);
}

FUZZ_TEST_S(fuzz_helper, Test_fuzz_r_tight_region, 2) {
    std::cout << "Test: " << __PRETTY_FUNCTION__ << "\n";

    // assuming that a test for int64 correlates to all types working

    // Arrange
    int64_t i64 = 0;

    bool i64_min = false;
    bool i64_upper = false;
    bool i64_middle = false;

    // Act
    for (int32_t i = 0; i < INT32_MAX; ++i) {
        dextool::fuzz_r(i64, INT64_MIN, INT64_MIN + 10);

        if (i64 == INT64_MIN) {
            i64_min = true;
        }
        // note: the random range is [x,y)
        if (i64 == INT64_MIN + 9) {
            i64_upper = true;
        }
        if (i64 == INT64_MIN + 4) {
            i64_middle = true;
        }

        if (i64_min && i64_upper && i64_middle) {
            return;
        }
    }

    // unable to generate the expected boundary values
    assert(0);
}
