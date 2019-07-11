# vim: filetype=cmake

file(GLOB_RECURSE SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/source/*.d)
list(APPEND SRC_FILES ${CMAKE_SOURCE_DIR}/plugin/source/dextool/plugin/main/standard.d)

set(EXE_NAME ${DEXTOOL_MAIN_EXE}-example)

build_d_executable(
    ${EXE_NAME}
    "${SRC_FILES}"
    "-I${CMAKE_CURRENT_LIST_DIR}/source -I${CMAKE_SOURCE_DIR}/source -I${CMAKE_SOURCE_DIR}/libs/dsrcgen/source -I${CMAKE_SOURCE_DIR}/libs/clang/source -I${CMAKE_SOURCE_DIR}/libs/libclang/source -I${CMAKE_SOURCE_DIR}/plugin/source -J${CMAKE_SOURCE_DIR}/libs/clang/resources -I${CMAKE_SOURCE_DIR}/vendor/taggedalgebraic/source -I${CMAKE_SOURCE_DIR}/vendor/colorlog/source -I${CMAKE_SOURCE_DIR}/vendor/blob_model/source"
    ""
    "dextool_dextool;dextool_cpptooling;dextool_plugin_utility;dextool_colorlog;dextool_blob_model"
)

collect_binary_in_root(${EXE_NAME})
