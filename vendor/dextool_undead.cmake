# vim: filetype=cmake

file(GLOB_RECURSE SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/undead/src/undead/*.d
)

compile_d_static_lib(dextool_undead "${SRC_FILES}" "" "" "")
