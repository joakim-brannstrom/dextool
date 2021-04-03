# vim: filetype=cmake

file(GLOB_RECURSE ANALYZE_SRC ${CMAKE_CURRENT_LIST_DIR}/source/dextool/plugin/mutate/backend/analyze/*.d)

list(APPEND DATABASE_STANDALONE_SRC
    ${CMAKE_CURRENT_LIST_DIR}/source/dextool/plugin/mutate/backend/database/schema.d
    ${CMAKE_CURRENT_LIST_DIR}/source/dextool/plugin/mutate/backend/database/standalone.d
    ${CMAKE_CURRENT_LIST_DIR}/source/dextool/plugin/mutate/backend/database/type.d
    )
set(DATABASE_SRC "${DATABASE_STANDALONE_SRC};${CMAKE_CURRENT_LIST_DIR}/source/dextool/plugin/mutate/backend/database/package.d")

file(GLOB_RECURSE MUTATION_TYPE_SRC ${CMAKE_CURRENT_LIST_DIR}/source/dextool/plugin/mutate/backend/mutation_type/*.d)
file(GLOB_RECURSE REPORT_SRC ${CMAKE_CURRENT_LIST_DIR}/source/dextool/plugin/mutate/backend/report/*.d)
file(GLOB_RECURSE TEST_MUTANT_SRC ${CMAKE_CURRENT_LIST_DIR}/source/dextool/plugin/mutate/backend/test_mutant/*.d)
file(GLOB BACKEND_SRC ${CMAKE_CURRENT_LIST_DIR}/source/dextool/plugin/mutate/backend/*.d)
file(GLOB_RECURSE FRONTEND_SRC ${CMAKE_CURRENT_LIST_DIR}/source/dextool/plugin/mutate/frontend/*.d)
file(GLOB SRC ${CMAKE_CURRENT_LIST_DIR}/source/dextool/plugin/mutate/*.d)

list(APPEND SRC ${MUTATION_TYPE_SRC} ${REPORT_SRC} ${TEST_MUTANT_SRC} ${BACKEND_SRC} ${FRONTEND_SRC})

set(dextool_mutate_database_flags
"
-I${CMAKE_CURRENT_LIST_DIR}/source
-I${CMAKE_SOURCE_DIR}/libs/clang/source
-I${CMAKE_SOURCE_DIR}/libs/libclang_ast/source
-I${CMAKE_SOURCE_DIR}/libs/dextool/source
-I${CMAKE_SOURCE_DIR}/libs/libclang/source
-I${CMAKE_SOURCE_DIR}/vendor/colorlog/source
-I${CMAKE_SOURCE_DIR}/vendor/d2sqlite3/source
-I${CMAKE_SOURCE_DIR}/vendor/miniorm/source
-I${CMAKE_SOURCE_DIR}/vendor/mylib/source
-I${CMAKE_SOURCE_DIR}/vendor/sumtype/src
-version=SqliteEnableColumnMetadata
-version=SqliteEnableUnlockNotify
")
compile_d_static_lib(dextool_mutate_standalone_database "${DATABASE_STANDALONE_SRC}"  "${dextool_mutate_database_flags}" "" "")
compile_d_static_lib(dextool_mutate_database "${DATABASE_SRC}"  "${dextool_mutate_database_flags}" "" "")

set(dextool_mutate_analyze_flags
"
-I${CMAKE_CURRENT_LIST_DIR}/source
-I${CMAKE_SOURCE_DIR}/libs/clang/source
-I${CMAKE_SOURCE_DIR}/libs/libclang_ast/source
-I${CMAKE_SOURCE_DIR}/libs/dextool/source
-I${CMAKE_SOURCE_DIR}/libs/dextool_clang_extensions/source
-I${CMAKE_SOURCE_DIR}/libs/libclang/source
-I${CMAKE_SOURCE_DIR}/plugin/source
-I${CMAKE_SOURCE_DIR}/source
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
-J${CMAKE_SOURCE_DIR}/libs/clang/resources
-version=SqliteEnableColumnMetadata
-version=SqliteEnableUnlockNotify
")
compile_d_static_lib(dextool_mutate_analyze "${ANALYZE_SRC}"  "${dextool_mutate_analyze_flags}" "" "")

set(flags "
-I${CMAKE_CURRENT_LIST_DIR}/source
-I${CMAKE_SOURCE_DIR}/libs/clang/source
-I${CMAKE_SOURCE_DIR}/libs/libclang_ast/source
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
-I${CMAKE_SOURCE_DIR}/vendor/undead/src
-J${CMAKE_SOURCE_DIR}/libs/clang/resources
-version=SqliteEnableColumnMetadata
-version=SqliteEnableUnlockNotify
"
)

set(EXE_NAME ${DEXTOOL_MAIN_EXE}-mutate)

# must use gold otherwise it doesn't link on centos7
build_d_executable(
    ${EXE_NAME}
    "${SRC};${CMAKE_SOURCE_DIR}/plugin/source/dextool/plugin/main/standard.d"
    "${flags}"
    ""
    "dextool_mutate_analyze;dextool_mutate_database;dextool_proc;dextool_automem;dextool_blob_model;dextool_dextool;dextool_libclang_ast;dextool_clang_extensions;dextool_miniorm;dextool_d2sqlite3;dextool_colorlog;dextool_toml;dextool_arsd;dextool_cachetools;dextool_mylib;dextool_sumtype"
)

collect_binary_in_root(${EXE_NAME})
create_link(${EXE_NAME} ${CMAKE_CURRENT_LIST_DIR}/data ${CMAKE_BINARY_DIR}/data/mutate)
create_link(${EXE_NAME} ${CMAKE_CURRENT_LIST_DIR}/data ${CMAKE_CURRENT_BINARY_DIR}/data/mutate)

install(TARGETS ${EXE_NAME} DESTINATION ${CMAKE_INSTALL_PREFIX}/bin)

file(GLOB_RECURSE DATA_FILES ${CMAKE_CURRENT_LIST_DIR}/data/*)
install(FILES ${DATA_FILES} DESTINATION ${CMAKE_INSTALL_PREFIX}/data/mutate)

compile_d_unittest(mutate "${SRC};${ANALYZE_SRC};${CMAKE_CURRENT_LIST_DIR}/ut_main.d" "${flags}" "" "dextool_mutate_analyze;dextool_mutate_database;dextool_proc;dextool_automem;dextool_colorlog;dextool_blob_model;dextool_dextool;dextool_libclang_ast;dextool_clang_extensions;dextool_miniorm;dextool_d2sqlite3;dextool_toml;dextool_arsd;dextool_cachetools;dextool_mylib;dextool_sumtype")

setup_integration_testing_env()

file(GLOB_RECURSE TEST_SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/test/*.d)
file(GLOB_RECURSE TESTDATA_FILES ${CMAKE_SOURCE_DIR}/test/testdata/* ${CMAKE_CURRENT_LIST_DIR}/testdata/*)
list(APPEND SUT_REUSED_FILES
    ${CMAKE_CURRENT_LIST_DIR}/source/dextool/plugin/mutate/backend/type.d
    ${CMAKE_CURRENT_LIST_DIR}/source/dextool/plugin/mutate/type.d
    )
compile_d_integration_test(${EXE_NAME} "${TEST_SRC_FILES};${SUT_REUSED_FILES}" "${flags}" "" "dextool_mutate_standalone_database;dextool_dextool_test;dextool_miniorm;dextool_d2sqlite3;dextool_dextool;dextool_mylib;dextool_sumtype" "${TESTDATA_FILES}")

# c/c++ code

add_executable(test_schemata_c_header ${CMAKE_CURRENT_LIST_DIR}/test/test_schemata_c_header.cpp)
target_include_directories(test_schemata_c_header PRIVATE ${CMAKE_CURRENT_LIST_DIR}/data)
add_unittest_to_check(test_schemata_c_header)

add_executable(test_covmap ${CMAKE_CURRENT_LIST_DIR}/test/test_covmap.cpp)
target_include_directories(test_covmap PRIVATE ${CMAKE_CURRENT_LIST_DIR}/data)
add_unittest_to_check(test_covmap)
