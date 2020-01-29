# vim: filetype=cmake

file(GLOB_RECURSE SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/cachetools/source/*.d
)

set(flags "-I${CMAKE_CURRENT_LIST_DIR}/automem/source")

compile_d_static_lib(dextool_cachetools "${SRC_FILES}" "${flags}" "" "")
