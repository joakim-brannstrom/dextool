# vim: filetype=cmake

file(GLOB SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/source/dsrcgen/*.d)

compile_d_static_lib(dextool_dsrcgen "${SRC_FILES}" "" "" "")
