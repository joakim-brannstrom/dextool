# vim: filetype=cmake

# This files purpose is to pull in the files that actually contain the working
# units. Keep this file simple.

add_library(gmock_gtest STATIC
    ${CMAKE_CURRENT_LIST_DIR}/fused_gmock/gmock-gtest-all.cc
    ${CMAKE_CURRENT_LIST_DIR}/fused_gmock/main.cc
    )
set_target_properties(gmock_gtest PROPERTIES
    COMPILE_FLAGS "-I${CMAKE_CURRENT_LIST_DIR}/fused_gmock"
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/
    )

add_dependencies(check_integration gmock_gtest)

include(dextool_dextool_test.cmake)

include(dextool_integration_test.cmake)
