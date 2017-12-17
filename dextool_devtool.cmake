# vim: filetype=cmake

file(GLOB SRC_FILES
    ${CMAKE_SOURCE_DIR}/source/devtool/tok_main.d
)

set(EXE_NAME devtool)

build_d_executable(
    ${EXE_NAME}
    "${SRC_FILES}"
    "-I${CMAKE_CURRENT_LIST_DIR}/source -I${CMAKE_SOURCE_DIR}/source -I${CMAKE_SOURCE_DIR}/dsrcgen/source -I${CMAKE_SOURCE_DIR}/clang -I${CMAKE_SOURCE_DIR}/libclang -I${CMAKE_SOURCE_DIR}/plugin/source -J${CMAKE_SOURCE_DIR}/clang/resources -I${CMAKE_SOURCE_DIR}/vendor/taggedalgebraic/source"
    "${LIBCLANG_LDFLAGS}"
    "dextool_dextool;dextool_cpptooling;dextool_plugin_utility"
)
