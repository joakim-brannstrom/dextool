# vim: filetype=cmake

file(GLOB_RECURSE SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/source/*.d)
file(GLOB_RECURSE SRC_MUTATE_FILES ${CMAKE_CURRENT_LIST_DIR}/../mutate/source/dextool/plugin/mutate/backend/*.d)

list(REMOVE_ITEM SRC_MUTATE_FILES ${CMAKE_CURRENT_LIST_DIR}/../mutate/source/dextool/plugin/mutate/runner.d)

list(APPEND SRC_FILES
    ${CMAKE_SOURCE_DIR}/plugin/source/dextool/plugin/main/standard.d
    ${SRC_MUTATE_FILES}
    )

set(EXE_NAME ${DEXTOOL_MAIN_EXE}-eqdetect)

build_d_executable(
    ${EXE_NAME}
    "${SRC_FILES}"
    "-I${CMAKE_CURRENT_LIST_DIR}/source -I${CMAKE_SOURCE_DIR}/source -I${CMAKE_SOURCE_DIR}/dsrcgen/source -I${CMAKE_SOURCE_DIR}/clang -I${CMAKE_SOURCE_DIR}/libclang -I${CMAKE_SOURCE_DIR}/plugin/source -J${CMAKE_SOURCE_DIR}/clang/resources -I${CMAKE_SOURCE_DIR}/vendor/taggedalgebraic/source -I${CMAKE_SOURCE_DIR}/vendor/d2sqlite3/source -I${CMAKE_SOURCE_DIR}/plugin/mutate/source -I${CMAKE_SOURCE_DIR}/dextool_clang_extensions/source"
    ""
    "dextool_dextool;dextool_cpptooling;dextool_plugin_utility;dextool_d2sqlite3;dextool_clang_extensions"
)

collect_binary_in_root(${EXE_NAME})

install(TARGETS ${EXE_NAME} DESTINATION ${CMAKE_INSTALL_PREFIX}/bin)
