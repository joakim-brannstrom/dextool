# vim: filetype=cmake

# set(LIBCLANG_INC "${CMAKE_CURRENT_LIST_DIR}/${LIBLLVM_MAJOR_VERSION}/source" CACHE STRING "path to libclang bindings")
# file(GLOB SRC_FILES ${LIBCLANG_INC}/clang/c/*.d)
#
# compile_d_static_lib(dextool_libclang "${SRC_FILES}" "" "" "")
# target_link_libraries(dextool_libclang ${LIBCLANG_LDFLAGS})

# add_custom_command(OUTPUT "${CMAKE_BINARY_DIR}/libclang.stamp"
#     COMMAND /bin/bash -c "${LIBCLANG_PREPROCESS_CMD} ${clang_config_INCLUDEDIR}/clang-c ${CMAKE_BINARY_DIR}/libclang ${llvm_config_CPPFLAGS}"
#     COMMAND_EXPAND_LISTS
#     COMMAND touch "${CMAKE_BINARY_DIR}/libclang.stamp"
#     COMMENT "Preprocess libclang-c"
#     )
# set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_MAKE_CLEAN_FILES "${CMAKE_BINARY_DIR}/libclang.stamp")
# add_custom_target("libclang_preprocess" DEPENDS "${CMAKE_BINARY_DIR}/libclang.stamp")

set(LIBCLANG_INC "-I${CMAKE_CURRENT_LIST_DIR}/source -P-I${clang_config_INCLUDEDIR}" CACHE STRING "path to preprocessed libclang headers")
list(APPEND SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/c/BuildSystem.c
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/c/CXCompilationDatabase.c
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/c/CXDiagnostic.c
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/c/CXErrorCode.c
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/c/CXFile.c
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/c/CXSourceLocation.c
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/c/CXString.c
    ${CMAKE_CURRENT_LIST_DIR}/source/clang/c/Index.c
    )

compile_d_static_lib(dextool_libclang "${SRC_FILES}" "${LIBCLANG_INC}" "" "")
target_link_libraries(dextool_libclang ${LIBCLANG_LDFLAGS})
