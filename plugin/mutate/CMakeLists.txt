# vim: filetype=cmake

file(GLOB_RECURSE SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/source/*.d)
list(APPEND SRC_FILES ${CMAKE_SOURCE_DIR}/plugin/source/dextool/plugin/main/standard.d)

set(EXE_NAME ${DEXTOOL_MAIN_EXE}-mutate)

set(flags "-I${CMAKE_CURRENT_LIST_DIR}/source -J${CMAKE_CURRENT_LIST_DIR}/view -I${CMAKE_SOURCE_DIR}/source -I${CMAKE_SOURCE_DIR}/dsrcgen/source -I${CMAKE_SOURCE_DIR}/libs/clang/source -I${CMAKE_SOURCE_DIR}/libs/libclang/source -I${CMAKE_SOURCE_DIR}/plugin/source -I${CMAKE_SOURCE_DIR}/libs/dextool_clang_extensions/source -I${CMAKE_SOURCE_DIR}/vendor/d2sqlite3/source -J${CMAKE_SOURCE_DIR}/libs/clang/resources -version=SqliteEnableColumnMetadata -version=SqliteEnableUnlockNotify -I${CMAKE_SOURCE_DIR}/vendor/taggedalgebraic/source -I${CMAKE_SOURCE_DIR}/vendor/colorlog/source -I${CMAKE_SOURCE_DIR}/vendor/toml/src -I${CMAKE_SOURCE_DIR}/vendor/arsd -I${CMAKE_SOURCE_DIR}/vendor/cachetools/source -I${CMAKE_SOURCE_DIR}/vendor/sumtype/src -I${CMAKE_SOURCE_DIR}/vendor/miniorm/source -I${CMAKE_SOURCE_DIR}/vendor/blob_model/source")

build_d_executable(
    ${EXE_NAME}
    "${SRC_FILES}"
    "${flags}"
    ""
    "dextool_blob_model;dextool_dextool;dextool_cpptooling;dextool_plugin_utility;dextool_clang_extensions;dextool_miniorm;dextool_d2sqlite3;dextool_colorlog;dextool_toml;dextool_arsd;dextool_cachetools"
)

collect_binary_in_root(${EXE_NAME})

install(TARGETS ${EXE_NAME} DESTINATION ${CMAKE_INSTALL_PREFIX}/bin)

list(REMOVE_ITEM SRC_FILES ${CMAKE_SOURCE_DIR}/plugin/source/dextool/plugin/main/standard.d)

list(APPEND SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/ut_main.d
)
compile_d_unittest(mutate "${SRC_FILES}" "${flags}" "" "dextool_blob_model;dextool_dextool;dextool_cpptooling;dextool_plugin_utility;dextool_clang_extensions;dextool_miniorm;dextool_d2sqlite3;dextool_toml;dextool_arsd;dextool_cachetools")

setup_integration_testing_env()

list(APPEND SUT_REUSED_FILES
    ${CMAKE_CURRENT_LIST_DIR}/source/dextool/plugin/mutate/backend/database/schema.d
    ${CMAKE_CURRENT_LIST_DIR}/source/dextool/plugin/mutate/backend/database/standalone.d
    ${CMAKE_CURRENT_LIST_DIR}/source/dextool/plugin/mutate/backend/database/type.d
    ${CMAKE_CURRENT_LIST_DIR}/source/dextool/plugin/mutate/backend/type.d
    ${CMAKE_CURRENT_LIST_DIR}/source/dextool/plugin/mutate/type.d
    )
file(GLOB_RECURSE TEST_SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/test/*.d)
file(GLOB_RECURSE TESTDATA_FILES ${CMAKE_SOURCE_DIR}/test/testdata/* ${CMAKE_CURRENT_LIST_DIR}/testdata/*)
compile_d_integration_test(${EXE_NAME} "${TEST_SRC_FILES};${SUT_REUSED_FILES}" "${flags}" "" "dextool_dextool_test;dextool_miniorm;dextool_d2sqlite3;dextool_dextool" "${TESTDATA_FILES}")
