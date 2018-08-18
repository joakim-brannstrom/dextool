# vim: filetype=cmake

file(GLOB_RECURSE SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/colorlog/source/*.d
)

compile_d_static_lib(dextool_colorlog "${SRC_FILES}" "" "" "")
