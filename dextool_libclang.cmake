# vim: filetype=cmake

file(GLOB SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/libclang/deimos/clang/*.d)
compile_d_static_lib(dextool_libclang "${SRC_FILES}" "" "" "")
