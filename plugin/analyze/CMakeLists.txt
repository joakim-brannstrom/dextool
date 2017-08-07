# vim: filetype=cmake

add_subdirectory(cpp_clang_extension)
set(DEXTOOL_CPP_EXTENSION_LDFLAGS
    "-L-L${CMAKE_CURRENT_BINARY_DIR}/cpp_clang_extension -L-ldextool_clang_extension \
    -L-lclangFrontendTool \
    -L-lclangRewriteFrontend \
    -L-lclangDynamicASTMatchers \
    -L-lclangFrontend \
    -L-lclangASTMatchers \
    -L-lclangParse \
    -L-lclangSerialization \
    -L-lclangRewrite \
    -L-lclangSema \
    -L-lclangEdit \
    -L-lclangAnalysis \
    -L-lclangAST \
    -L-lclangLex \
    -L-lclangBasic \
    -L-lstdc++ -L-lm -L-lc"
    )

file(GLOB_RECURSE SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/source/*.d)
list(APPEND SRC_FILES ${CMAKE_SOURCE_DIR}/plugin/source/dextool/plugin/main/standard.d)

set(EXE_NAME ${DEXTOOL_MAIN_EXE}-analyze)

build_d_executable(
    ${EXE_NAME}
    "${SRC_FILES}"
    "-I${CMAKE_CURRENT_LIST_DIR}/source -I${CMAKE_SOURCE_DIR}/source -I${CMAKE_SOURCE_DIR}/dsrcgen/source -I${CMAKE_SOURCE_DIR}/clang -I${CMAKE_SOURCE_DIR}/libclang -I${CMAKE_SOURCE_DIR}/plugin/source -J${CMAKE_SOURCE_DIR}/clang/resources"
    "${DEXTOOL_CPP_EXTENSION_LDFLAGS} ${LIBCLANG_LDFLAGS} ${LIBLLVM_LDFLAGS}"
    "dextool_dextool;dextool_cpptooling;dextool_plugin_utility"
)
add_dependencies(${EXE_NAME} dextool_clang_extension)

collect_binary_in_root(${EXE_NAME})

install(TARGETS ${EXE_NAME} DESTINATION ${CMAKE_INSTALL_PREFIX}/bin)

setup_integration_testing_env()
compile_d_integration_test(${EXE_NAME} "${CMAKE_SOURCE_DIR}/test/integration_main.d;${CMAKE_CURRENT_LIST_DIR}/test/integration.d" "" "" "dextool_scriptlike;dextool_dextool_test")
