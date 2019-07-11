# vim: filetype=cmake

file(GLOB_RECURSE DEXTOOL_TEST_FILES
    ${CMAKE_CURRENT_LIST_DIR}/source/*.d
)

set(flags "-I${CMAKE_SOURCE_DIR}/vendor/unit-threaded/subpackages/exception/source")

compile_d_static_lib(dextool_dextool_test "${DEXTOOL_TEST_FILES}" "${flags}" "" "")
