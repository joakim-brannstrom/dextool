cmake_minimum_required(VERSION 3.10)
project(flawless)
include(CTest)

add_library(gmock_gtest STATIC
    ${CMAKE_CURRENT_LIST_DIR}/../../../../vendor/fused_gmock/gmock-gtest-all.cc
    ${CMAKE_CURRENT_LIST_DIR}/../../../../vendor/fused_gmock/main.cc
    )
target_include_directories(gmock_gtest PUBLIC "${CMAKE_CURRENT_LIST_DIR}/../../../../vendor/fused_gmock")
target_link_libraries(gmock_gtest PUBLIC "-lpthread")

add_library(impl src/impl.cpp)
target_compile_definitions(impl PUBLIC "${EXTRA_TESTS}")
target_include_directories(impl PUBLIC ${CMAKE_CURRENT_LIST_DIR}/src)

add_executable(flawless test/tests.cpp)
target_link_libraries(flawless impl gmock_gtest)
add_test(NAME flawless COMMAND flawless)
