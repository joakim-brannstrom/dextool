#include "gmock/gmock.h"

#include "test_double_gmock.hpp"

using testing::_;
using testing::Return;

class Functions : public testing::Test {
public:
    Functions() : mock(), adapter(mock) {}

    TestDouble::MockI_TestDouble mock;
    TestDouble::Adapter adapter;
};

TEST_F(Functions, InstantiateTest) {
}

TEST_F(Functions, PassThroughTest) {
    EXPECT_CALL(mock, func_void());
    EXPECT_CALL(mock, func_one_named(42));
    EXPECT_CALL(mock, func_two_named(43, 84));
    EXPECT_CALL(mock, func_three_named(44, 85, 101));

    func_void();
    func_one_named(42);
    func_two_named(43, 84);
    func_three_named(44, 85, 101);
}

TEST_F(Functions, PassThroughTestOfConstFunctions) {
    EXPECT_CALL(mock, c_func_one_named(45));
    EXPECT_CALL(mock, c_func_two_named(46, 86));
    EXPECT_CALL(mock, c_func_three_named(46, 86, 102));

    c_func_one_named(45);
    c_func_two_named(46, 86);
    c_func_three_named(46, 86, 102);
}

TEST_F(Functions, PassThroughTestOfVariadicFunction) {
    EXPECT_CALL(mock, func_variadic());
    const char* the_one = "the one";
    EXPECT_CALL(mock, func_variadic_one_unnamed(const_cast<char*>(the_one)));

    func_variadic();
    func_variadic_one_unnamed(const_cast<char*>(the_one));
}

TEST_F(Functions, PassThroughTestOfUnnamedParams) {
    EXPECT_CALL(mock, unnamed_params(47, 87));

    unnamed_params(47, 87);
}

TEST_F(Functions, ReturnValueTest) {
    EXPECT_CALL(mock, func_return()).WillOnce(Return(42));
    EXPECT_CALL(mock, func_one_named(_)).WillOnce(Return(43));

    EXPECT_CALL(mock, c_func_return()).WillOnce(Return(44));
    EXPECT_CALL(mock, c_func_one_named(_)).WillOnce(Return(45));

    EXPECT_EQ(42, func_return());
    EXPECT_EQ(43, func_one_named(0));
    EXPECT_EQ(44, c_func_return());
    EXPECT_EQ(45, c_func_one_named(0));
}

static int test_func_two_params(int a, int b) {
    return 42;
}

TEST_F(Functions, PassThroughTestOfFuncPtr) {
    EXPECT_CALL(mock, fun(&test_func_two_params, _));
    EXPECT_CALL(mock, func_ptr_arg(&test_func_two_params, 42));

    Something_Big junk;
    fun(&test_func_two_params, junk);
    func_ptr_arg(&test_func_two_params, 42);
}

static void test_func_one_param(int a) {
}

TEST_F(Functions, ReturnFuncPtrTest) {
    EXPECT_CALL(mock, func_return_func_ptr()).WillOnce(Return(&test_func_one_param));

    EXPECT_EQ(&test_func_one_param, func_return_func_ptr());
}

TEST_F(Functions, GlueLayerOfTypedefFuncTest) {
    EXPECT_CALL(mock, gun_func(42));

    gun_func(42);
}

TEST_F(Functions, ArrayParamTest) {
    int arr1[16] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15};
    MyIntType arr2[16] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15};

    EXPECT_CALL(mock, array_func(_, _, arr1));
    EXPECT_CALL(mock, array_func_param_typedef(arr2));

    array_func(42, reinterpret_cast<int*>(42), arr1);
    array_func_param_typedef(arr2);
}

TEST_F(Functions, EnumBugTest) {
    EXPECT_CALL(mock, func_exhibit_type_bug_variant1(ANKA));
    EXPECT_CALL(mock, func_exhibit_type_bug_variant2()).WillOnce(Return(ANKA));
    EXPECT_CALL(mock, func_with_enum_param(ANKA));
    EXPECT_CALL(mock, func_with_enum_param_and_return(ANKA)).WillOnce(Return(ANKA));

    func_exhibit_type_bug_variant1(ANKA);
    EXPECT_EQ(ANKA, func_exhibit_type_bug_variant2());
    func_with_enum_param(ANKA);
    EXPECT_EQ(ANKA, func_with_enum_param_and_return(ANKA));
}
