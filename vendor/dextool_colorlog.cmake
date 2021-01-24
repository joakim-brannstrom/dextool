# vim: filetype=cmake

set(flags "-I${CMAKE_CURRENT_LIST_DIR}/proc/source
-I${CMAKE_CURRENT_LIST_DIR}/mylib/source
")

file(GLOB_RECURSE SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/colorlog/source/*.d
)

compile_d_static_lib(dextool_colorlog "${SRC_FILES}" "${flags}" "" "dextool_mylib;dextool_sumtype")
