# vim: filetype=cmake

add_dependencies(check_integration gmock_gtest)

include(dextool_dextool_test.cmake)
include(dextool_integration_test.cmake)
