# vim: filetype=cmake

file(GLOB_RECURSE SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/source/*.d)
list(APPEND SRC_FILES ${CMAKE_SOURCE_DIR}/plugin/source/dextool/plugin/main/standard.d)

set(EXE_NAME ${DEXTOOL_MAIN_EXE}-uml)

set(flags "-I${CMAKE_CURRENT_LIST_DIR}/source -I${CMAKE_SOURCE_DIR}/source -I${CMAKE_SOURCE_DIR}/dsrcgen/source -I${CMAKE_SOURCE_DIR}/clang -I${CMAKE_SOURCE_DIR}/libclang -I${CMAKE_SOURCE_DIR}/plugin/source -J${CMAKE_SOURCE_DIR}/clang/resources")

build_d_executable(
    ${EXE_NAME}
    "${SRC_FILES}"
    "${flags}"
    "${LIBCLANG_LDFLAGS}"
    "dextool_dextool;dextool_cpptooling;dextool_plugin_utility"
)

collect_binary_in_root(${EXE_NAME})

install(TARGETS ${EXE_NAME} DESTINATION ${CMAKE_INSTALL_PREFIX}/bin)

list(REMOVE_ITEM SRC_FILES ${CMAKE_SOURCE_DIR}/plugin/source/dextool/plugin/main/standard.d)

list(APPEND SRC_FILES
    ${CMAKE_SOURCE_DIR}/source/test/clang_util.d
    ${CMAKE_SOURCE_DIR}/source/test/helpers.d
    ${CMAKE_SOURCE_DIR}/source/test/component/plantuml.d
    ${CMAKE_CURRENT_LIST_DIR}/ut_main.d
)
compile_d_unittest(uml "${SRC_FILES}" "${flags}" "${LIBCLANG_LDFLAGS}" "dextool_dextool;dextool_cpptooling;dextool_plugin_utility")
