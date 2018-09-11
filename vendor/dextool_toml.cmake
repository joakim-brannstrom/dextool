# vim: filetype=cmake

file(GLOB_RECURSE SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/toml/src/toml/*.d
)

compile_d_static_lib(dextool_toml "${SRC_FILES}" "" "" "")
