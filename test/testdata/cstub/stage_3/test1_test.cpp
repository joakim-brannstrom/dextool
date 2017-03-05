#include "gmock/gmock.h"

#include "test_double_gmock.hpp"

TEST(Instantiate, Gmock) {
    TestDouble::MockI_TestDouble mock;
    TestDouble::Adapter adapter(mock);

    // EXPECT_CALL(mock,

}
