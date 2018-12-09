# vim: filetype=cmake

file(GLOB_RECURSE SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/arsd/arsd/*.d
)

compile_d_static_lib(dextool_arsd "${SRC_FILES}" "" "" "")
