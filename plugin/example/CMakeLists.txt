# vim: filetype=cmake

file(GLOB_RECURSE SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/source/*.d)
list(APPEND SRC_FILES ${CMAKE_SOURCE_DIR}/plugin/source/dextool/plugin/main/standard.d)

set(EXE_NAME ${DEXTOOL_MAIN_EXE}-example)

build_d_executable(
    ${EXE_NAME}
    "${SRC_FILES}"
    "-I${CMAKE_CURRENT_LIST_DIR}/source
    -I${CMAKE_SOURCE_DIR}/libs/cpptooling/source
    -I${CMAKE_SOURCE_DIR}/source
    -I${CMAKE_SOURCE_DIR}/libs/dextool/source
    -I${CMAKE_SOURCE_DIR}/libs/dsrcgen/source
    -I${CMAKE_SOURCE_DIR}/libs/clang/source
    ${LIBCLANG_INC}
    -I${CMAKE_SOURCE_DIR}/libs/libclang_ast/source
    -I${CMAKE_SOURCE_DIR}/plugin/source
    -I${CMAKE_SOURCE_DIR}/vendor/colorlog/source
    -I${CMAKE_SOURCE_DIR}/vendor/mylib/source
    -I${CMAKE_SOURCE_DIR}/vendor/sumtype/src
    -I${CMAKE_SOURCE_DIR}/vendor/undead/src
    -I${CMAKE_SOURCE_DIR}/vendor/blob_model/source"
    "${LIBCLANG_LDFLAGS} ${LIBCLANG_LIBS}"
    "dextool_dextool;dextool_cpptooling;dextool_libclang_ast;dextool_colorlog;dextool_blob_model;dextool_mylib"
)

collect_binary_in_root(${EXE_NAME})
