/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2019
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#include "impl.hpp"
#include <gtest/gtest.h>

// These are the original test cases.
// They are the pretty obvious an simple test cases that one would expect to
// see in a test suite.
TEST(Compare, SameString) {
    EXPECT_TRUE(compare("university", "university"));
    EXPECT_TRUE(compare("course", "course"));
}

TEST(Compare, EmptyString) { EXPECT_TRUE(compare("", "")); }

TEST(Compare, DiffString) {
    EXPECT_FALSE(compare("university", "course"));
    EXPECT_FALSE(compare("lecture", "course"));
    EXPECT_FALSE(compare("precision", "exactness"));
}

// Added tests to kill the RORp mutants that survived.
#ifdef TEST_RORP

TEST(RORp, LessThan) { EXPECT_FALSE(compare("universit", "university")); }

TEST(RORp, CharsGreaterThan) { EXPECT_FALSE(compare("bbb", "aaa")); }

#endif

#ifdef TEST_ABS

TEST(ABS, CharWrapAroundAtEnd) { EXPECT_FALSE(compare("university\xff", "university\x01")); }

#endif

#ifdef TEST_ABS2

TEST(ABS, CharWrapAroundAtBeginning) { EXPECT_FALSE(compare("\xffuniversity", "\x01university")); }

#endif

// A test case that show the bug that exists in the implementation
#ifdef REAL_BUG

TEST(Bug, Test) { EXPECT_FALSE(compare("foo", "moo")); }

#endif
