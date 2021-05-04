# vim: filetype=cmake

file(GLOB_RECURSE SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/source/*.d)
list(APPEND SRC_FILES ${CMAKE_SOURCE_DIR}/plugin/source/dextool/plugin/main/standard.d)

set(EXE_NAME ${DEXTOOL_MAIN_EXE}-fuzzer)
set(flags "-I${CMAKE_CURRENT_LIST_DIR}/source
-I${CMAKE_SOURCE_DIR}/libs/clang/source
-I${CMAKE_SOURCE_DIR}/libs/cpptooling/source
-I${CMAKE_SOURCE_DIR}/libs/dextool/source
-I${CMAKE_SOURCE_DIR}/libs/dsrcgen/source
-I${LIBCLANG_INC}
-I${CMAKE_SOURCE_DIR}/libs/libclang_ast/source
-I${CMAKE_SOURCE_DIR}/plugin/source
-I${CMAKE_SOURCE_DIR}/source
-I${CMAKE_SOURCE_DIR}/vendor/blob_model/source
-I${CMAKE_SOURCE_DIR}/vendor/colorlog/source
-I${CMAKE_SOURCE_DIR}/vendor/mylib/source
-I${CMAKE_SOURCE_DIR}/vendor/sumtype/src
-J${CMAKE_SOURCE_DIR}/libs/clang/resources
")

build_d_executable(
    ${EXE_NAME}
    "${SRC_FILES}"
    "${flags}"
    ""
    "dextool_dextool;dextool_cpptooling;dextool_libclang_ast;dextool_colorlog;dextool_mylib;dextool_sumtype"
)

collect_binary_in_root(${EXE_NAME})

install(TARGETS ${EXE_NAME} DESTINATION ${CMAKE_INSTALL_PREFIX}/bin)

list(REMOVE_ITEM SRC_FILES ${CMAKE_SOURCE_DIR}/plugin/source/dextool/plugin/main/standard.d)

set(dextoolfuzz_SRC
    ${CMAKE_CURRENT_LIST_DIR}/support/afl_integration.cpp
    ${CMAKE_CURRENT_LIST_DIR}/support/fuzz_helper.cpp
    ${CMAKE_CURRENT_LIST_DIR}/support/pcg_basic.c
)

add_library(dextoolfuzz STATIC ${dextoolfuzz_SRC})
set_target_properties(dextoolfuzz PROPERTIES
    COMPILE_FLAGS "-O3 -I${CMAKE_CURRENT_LIST_DIR}/support"
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/
    )

add_library(dextoolfuzz_g STATIC ${dextoolfuzz_SRC})
set_target_properties(dextoolfuzz_g PROPERTIES
    COMPILE_FLAGS "-g -I${CMAKE_CURRENT_LIST_DIR}/support"
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/
    )

install(TARGETS dextoolfuzz dextoolfuzz_g ARCHIVE DESTINATION lib)

setup_integration_testing_env()

file(GLOB_RECURSE TESTDATA_FILES ${CMAKE_CURRENT_LIST_DIR}/test/testdata/*)
compile_d_integration_test(${EXE_NAME} "${CMAKE_SOURCE_DIR}/test/integration_main.d;${CMAKE_CURRENT_LIST_DIR}/test/integration.d" "" "" "dextool_dextool_test" "${TESTDATA_FILES}")

# Additional test environment
if (BUILD_TEST)
    execute_process(
        COMMAND ${CMAKE_BINARY_DIR}/symlink ${CMAKE_CURRENT_LIST_DIR}/support ${CMAKE_CURRENT_BINARY_DIR}/support
        )
endif()
