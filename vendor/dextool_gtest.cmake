# vim: filetype=cmake

add_library(gmock_gtest STATIC
    ${CMAKE_CURRENT_LIST_DIR}/fused_gmock/gmock-gtest-all.cc
    ${CMAKE_CURRENT_LIST_DIR}/fused_gmock/main.cc
    )
set_target_properties(gmock_gtest PROPERTIES
    COMPILE_FLAGS "-I${CMAKE_CURRENT_LIST_DIR}/fused_gmock"
    )
