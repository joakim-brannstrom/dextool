/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
/// This file contains the one-true-file needed to be included to use the
/// dextool support library.
#ifndef DEXTOOL_HPP
#define DEXTOOL_HPP

#include "dextool/internal_extern.hpp"
#include "dextool/types.hpp"

#include "dextool/data_source.hpp"
#include "dextool/fuzz_helper.hpp"
#include "dextool/fuzz_runner.hpp"
#include "dextool/i_fuzz.hpp"
#include "dextool/range_check.hpp"

#define DEXTOOL_FUZZ_CLASS_NAME(test_case_name, test_name) test_case_name##_##test_name##_Fuzz

#define DEXTOOL_FACTORY_INSTANCE__(test_case_name, test_name, test_line) test_case_name##_##test_name##_Fuzz_Instance##test_line
#define DEXTOOL_FACTORY_INSTANCE_(test_case_name, test_name, test_line) DEXTOOL_FACTORY_INSTANCE__(test_case_name, test_name, test_line)
#define DEXTOOL_FACTORY_INSTANCE(test_case_name, test_name) DEXTOOL_FACTORY_INSTANCE_(test_case_name, test_name, __LINE__)

#define FUZZ_TEST_(test_case_name, test_name, parent_class, test_seq) \
    class DEXTOOL_FUZZ_CLASS_NAME(test_case_name, test_name) : public parent_class { \
    public: \
        DEXTOOL_FUZZ_CLASS_NAME(test_case_name, test_name)() {} \
    private: \
        virtual void test_body(); \
    }; \
    static dextool::FuzzFactoryImpl<DEXTOOL_FUZZ_CLASS_NAME(test_case_name, test_name), test_seq> DEXTOOL_FACTORY_INSTANCE(test_case_name, test_name); \
    void DEXTOOL_FUZZ_CLASS_NAME(test_case_name, test_name)::test_body()

/// Create, instantiate and register a fuzz test.
#define FUZZ_TEST(test_case_name, test_name) \
    FUZZ_TEST_(test_case_name, test_name, ::dextool::Fuzz, INT64_MAX)

/// Create, instantiate and register a fuzz test derived from a fixture.
#define FUZZ_TEST_F(test_fixture, test_name) \
    FUZZ_TEST_(test_fixture, test_name, test_fixture, INT64_MAX)

/// Create, instantiate and register a fuzz test.
/// Use when a stable execution order is needed by specifying a sequence number.
#define FUZZ_TEST_S(test_case_name, test_name, test_seq) \
    FUZZ_TEST_(test_case_name, test_name, ::dextool::Fuzz, test_seq)

/// Create, instantiate and register a fuzz test derived from a fixture.
/// Use when a stable execution order is needed by specifying a sequence number.
#define FUZZ_TEST_FS(test_fixture, test_name, test_seq) \
    FUZZ_TEST_(test_fixture, test_name, test_fixture, test_seq)

#endif // DEXTOOL_HPP
