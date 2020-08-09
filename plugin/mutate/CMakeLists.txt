# vim: filetype=cmake

file(GLOB_RECURSE SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/source/*.d)
list(APPEND SRC_FILES ${CMAKE_SOURCE_DIR}/plugin/source/dextool/plugin/main/standard.d)

set(EXE_NAME ${DEXTOOL_MAIN_EXE}-mutate)

set(flags "
-I${CMAKE_SOURCE_DIR}/dsrcgen/source
-I${CMAKE_SOURCE_DIR}/libs/clang/source
-I${CMAKE_SOURCE_DIR}/libs/cpptooling/source
-I${CMAKE_SOURCE_DIR}/libs/dextool/source
-I${CMAKE_SOURCE_DIR}/libs/dextool_clang_extensions/source
-I${CMAKE_SOURCE_DIR}/libs/libclang/source
-I${CMAKE_SOURCE_DIR}/plugin/source
-I${CMAKE_SOURCE_DIR}/source
-I${CMAKE_SOURCE_DIR}/vendor/arsd
-I${CMAKE_SOURCE_DIR}/vendor/automem/source
-I${CMAKE_SOURCE_DIR}/vendor/blob_model/source
-I${CMAKE_SOURCE_DIR}/vendor/cachetools/source
-I${CMAKE_SOURCE_DIR}/vendor/colorlog/source
-I${CMAKE_SOURCE_DIR}/vendor/d2sqlite3/source
-I${CMAKE_SOURCE_DIR}/vendor/miniorm/source
-I${CMAKE_SOURCE_DIR}/vendor/mylib/source
-I${CMAKE_SOURCE_DIR}/vendor/proc/source
-I${CMAKE_SOURCE_DIR}/vendor/sumtype/src
-I${CMAKE_SOURCE_DIR}/vendor/taggedalgebraic/source
-I${CMAKE_SOURCE_DIR}/vendor/toml/src
-J${CMAKE_CURRENT_LIST_DIR}/views
-J${CMAKE_SOURCE_DIR}/libs/clang/resources
-version=SqliteEnableColumnMetadata
-version=SqliteEnableUnlockNotify
"
)

build_d_executable(
    ${EXE_NAME}
    "${SRC_FILES}"
    "${flags}"
    ""
    "dextool_proc;dextool_automem;dextool_blob_model;dextool_dextool;dextool_cpptooling;dextool_plugin_utility;dextool_clang_extensions;dextool_miniorm;dextool_d2sqlite3;dextool_colorlog;dextool_toml;dextool_arsd;dextool_cachetools;dextool_mylib;dextool_sumtype"
)

collect_binary_in_root(${EXE_NAME})

install(TARGETS ${EXE_NAME} DESTINATION ${CMAKE_INSTALL_PREFIX}/bin)

list(REMOVE_ITEM SRC_FILES ${CMAKE_SOURCE_DIR}/plugin/source/dextool/plugin/main/standard.d)

list(APPEND SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/ut_main.d
)
compile_d_unittest(mutate "${SRC_FILES}" "${flags}" "" "dextool_proc;dextool_automem;dextool_colorlog;dextool_blob_model;dextool_dextool;dextool_cpptooling;dextool_plugin_utility;dextool_clang_extensions;dextool_miniorm;dextool_d2sqlite3;dextool_toml;dextool_arsd;dextool_cachetools;dextool_mylib;dextool_sumtype")

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
compile_d_integration_test(${EXE_NAME} "${TEST_SRC_FILES};${SUT_REUSED_FILES}" "${flags}" "" "dextool_dextool_test;dextool_miniorm;dextool_d2sqlite3;dextool_dextool;dextool_mylib;dextool_sumtype" "${TESTDATA_FILES}")

# c/c++ code

add_executable(test_schemata_c_header ${CMAKE_CURRENT_LIST_DIR}/test/test_schemata_c_header.cpp)
target_include_directories(test_schemata_c_header PRIVATE ${CMAKE_CURRENT_LIST_DIR}/views)
add_unittest_to_check(test_schemata_c_header)
