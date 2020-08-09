# vim: filetype=cmake

set(flags "-I${CMAKE_CURRENT_LIST_DIR}/mylib/source -I${CMAKE_CURRENT_LIST_DIR}/sumtype/src")
file(GLOB_RECURSE SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/mylib/source/*/*.d)

compile_d_static_lib(
    dextool_mylib
    "${SRC_FILES}"
    "${flags}"
    ""
    "dextool_sumtype"
)

compile_d_unittest(
    dextool_mylib_tests
    "${SRC_FILES};"
    "${flags} -main"
    ""
    "dextool_sumtype"
)
