# vim: filetype=cmake

file(GLOB_RECURSE SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/source/*.d)
list(APPEND SRC_FILES ${CMAKE_SOURCE_DIR}/plugin/source/dextool/plugin/main/standard.d)

set(EXE_NAME ${DEXTOOL_MAIN_EXE}-mutate)

set(flags "-I${CMAKE_CURRENT_LIST_DIR}/source -I${CMAKE_SOURCE_DIR}/source -I${CMAKE_SOURCE_DIR}/dsrcgen/source -I${CMAKE_SOURCE_DIR}/clang -I${CMAKE_SOURCE_DIR}/libclang -I${CMAKE_SOURCE_DIR}/plugin/source -I${CMAKE_SOURCE_DIR}/dextool_clang_extensions/source -J${CMAKE_SOURCE_DIR}/clang/resources")

build_d_executable(
    ${EXE_NAME}
    "${SRC_FILES}"
    "${flags}"
    ""
    "dextool_dextool;dextool_cpptooling;dextool_plugin_utility;dextool_clang_extensions"
)

collect_binary_in_root(${EXE_NAME})

install(TARGETS ${EXE_NAME} DESTINATION ${CMAKE_INSTALL_PREFIX}/bin)

setup_integration_testing_env()

file(GLOB_RECURSE TEST_SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/test/*.d)
file(GLOB_RECURSE TESTDATA_FILES ${CMAKE_SOURCE_DIR}/test/testdata/* ${CMAKE_CURRENT_LIST_DIR}/testdata/*)
compile_d_integration_test(${EXE_NAME} "${TEST_SRC_FILES}" "" "" "dextool_scriptlike;dextool_dextool_test" "${TESTDATA_FILES}")
