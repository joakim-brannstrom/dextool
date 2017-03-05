#include "gmock/gmock.h"

#include "test_double_gmock.hpp"

using testing::_;
using testing::Return;

TEST(Functions, InstantiateTest) {
    TestDouble::MockI_TestDouble mock;
    TestDouble::Adapter adapter(mock);
}

TEST(Functions, UseExpectTest) {
    TestDouble::MockI_TestDouble mock;
    TestDouble::Adapter adapter(mock);

    EXPECT_CALL(mock, func_void());

    func_void();
}

TEST(Functions, ValueReturnTest) {
    TestDouble::MockI_TestDouble mock;
    TestDouble::Adapter adapter(mock);

    EXPECT_CALL(mock, func_return())
    .WillOnce(Return(42));

    EXPECT_EQ(42, func_return());
}
