# vim: filetype=cmake

file(GLOB_RECURSE SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/source/microrm/*.d
)

set(flags "-I${CMAKE_SOURCE_DIR}/vendor/d2sqlite3/source")

compile_d_static_lib(dextool_microrm "${SRC_FILES}" "${flags}" "" "dextool_d2sqlite3")
