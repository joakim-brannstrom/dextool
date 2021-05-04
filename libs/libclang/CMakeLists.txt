# vim: filetype=cmake

set(LIBCLANG_INC "${CMAKE_CURRENT_LIST_DIR}/${LIBLLVM_MAJOR_VERSION}/source" CACHE STRING "path to libclang bindings")
file(GLOB SRC_FILES ${LIBCLANG_INC}/clang/c/*.d)

compile_d_static_lib(dextool_libclang "${SRC_FILES}" "" "" "")
target_link_libraries(dextool_libclang ${LIBCLANG_LDFLAGS})
