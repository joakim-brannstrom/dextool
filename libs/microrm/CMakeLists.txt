# vim: filetype=cmake

file(GLOB_RECURSE SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/source/microrm/*.d
)

set(flags "-I${CMAKE_SOURCE_DIR}/vendor/d2sqlite3/source -I${CMAKE_SOURCE_DIR}/vendor/sumtype/src")
set(deps "dextool_d2sqlite3;dextool_sumtype")

compile_d_static_lib(dextool_microrm "${SRC_FILES}" "${flags}" "" "${deps}")

list(APPEND SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/ut_main.d
)
compile_d_unittest(microrm "${SRC_FILES}" "${flags}" "" "${deps}")
