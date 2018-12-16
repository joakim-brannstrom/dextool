# vim: filetype=cmake

file(GLOB_RECURSE SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/cachetools/source/*.d
)

compile_d_static_lib(dextool_cachetools "${SRC_FILES}" "" "" "")
