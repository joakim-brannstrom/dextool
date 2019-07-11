# vim: filetype=cmake

file(GLOB_RECURSE SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/source/*.d)
list(APPEND SRC_FILES ${CMAKE_SOURCE_DIR}/plugin/source/dextool/plugin/main/standard.d)

set(EXE_NAME ${DEXTOOL_MAIN_EXE}-analyze)

set(flags
    "-I${CMAKE_CURRENT_LIST_DIR}/source -I${CMAKE_SOURCE_DIR}/libs/dextool/source -I${CMAKE_SOURCE_DIR}/source -I${CMAKE_SOURCE_DIR}/libs/dsrcgen/source -I${CMAKE_SOURCE_DIR}/libs/clang/source -I${CMAKE_SOURCE_DIR}/libs/libclang/source -I${CMAKE_SOURCE_DIR}/plugin/source -I${CMAKE_SOURCE_DIR}/libs/dextool_clang_extensions/source -J${CMAKE_SOURCE_DIR}/libs/clang/resources -I${CMAKE_SOURCE_DIR}/vendor/taggedalgebraic/source -I${CMAKE_SOURCE_DIR}/vendor/colorlog/source -I${CMAKE_SOURCE_DIR}/vendor/blob_model/source"
    )

build_d_executable(
    ${EXE_NAME}
    "${SRC_FILES}"
    "${flags}"
    ""
    "dextool_dextool;dextool_cpptooling;dextool_plugin_utility;dextool_clang_extensions;dextool_colorlog;dextool_blob_model"
)

collect_binary_in_root(${EXE_NAME})

install(TARGETS ${EXE_NAME} DESTINATION ${CMAKE_INSTALL_PREFIX}/bin)

setup_integration_testing_env()

file(GLOB_RECURSE TESTDATA_FILES ${CMAKE_CURRENT_LIST_DIR}/test/testdata/*)
compile_d_integration_test(${EXE_NAME} "${CMAKE_SOURCE_DIR}/test/integration_main.d;${CMAKE_CURRENT_LIST_DIR}/test/integration.d" "" "" "dextool_dextool_test" "${TESTDATA_FILES}")
