# vim: filetype=cmake

set(flags "-I${CMAKE_CURRENT_LIST_DIR}/miniorm/source -I${CMAKE_SOURCE_DIR}/vendor/d2sqlite3/source -I${CMAKE_SOURCE_DIR}/vendor/sumtype/src ")
file(GLOB_RECURSE SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/miniorm/source/miniorm/*.d)

compile_d_static_lib(
    dextool_miniorm
    "${SRC_FILES}"
    "${flags}"
    ""
    "dextool_sumtype;dextool_d2sqlite3"
)
compile_d_unittest(
    dextool_miniorm_tests
    "${SRC_FILES};${CMAKE_CURRENT_LIST_DIR}/miniorm/ut.d"
    "${flags}"
    ""
    "dextool_sumtype;dextool_d2sqlite3"
)
