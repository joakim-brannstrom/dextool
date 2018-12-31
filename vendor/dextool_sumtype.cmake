# vim: filetype=cmake

set(flags "-I${CMAKE_CURRENT_LIST_DIR}/sumtype/src")
file(GLOB_RECURSE SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/sumtype/src/*.d)

compile_d_static_lib(
    dextool_sumtype
    "${SRC_FILES}"
    "${flags}"
    ""
    ""
)
compile_d_unittest(
    dextool_sumtype_tests
    "${SRC_FILES};"
    "${flags} -main"
    ""
    ""
)
