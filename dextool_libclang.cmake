# vim: filetype=cmake

file(GLOB SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/libclang/clang/c/*.d)
compile_d_static_lib(dextool_libclang "${SRC_FILES}" "" "" "")
target_link_libraries(dextool_libclang ${LIBCLANG_LDFLAGS})
