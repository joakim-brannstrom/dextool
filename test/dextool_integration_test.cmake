# vim: filetype=cmake

file(GLOB_RECURSE SCRIPTLIKE_FILES
    ${CMAKE_CURRENT_LIST_DIR}/scriptlike/src/*.d
)

compile_d_static_lib(dextool_scriptlike "${SCRIPTLIKE_FILES}" "" "" "")

file(GLOB SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/external_main.d
    ${CMAKE_CURRENT_LIST_DIR}/c_tests.d
    ${CMAKE_CURRENT_LIST_DIR}/cpp_tests.d
    ${CMAKE_CURRENT_LIST_DIR}/graphml_tests.d
    ${CMAKE_CURRENT_LIST_DIR}/plantuml_tests.d
)

set(flags "-I${CMAKE_CURRENT_LIST_DIR}/source")

compile_d_test(integration "${SRC_FILES}" "${flags}" "" "dextool_scriptlike")

# Setup expected test environment around the integration test binary
execute_process(
    COMMAND ln -sfT ${CMAKE_CURRENT_LIST_DIR}/fused_gmock ${CMAKE_CURRENT_BINARY_DIR}/fused_gmock
    COMMAND ln -sfT ${CMAKE_CURRENT_LIST_DIR}/testdata ${CMAKE_CURRENT_BINARY_DIR}/testdata
    COMMAND ln -sfT ${CMAKE_BINARY_DIR} ${CMAKE_CURRENT_BINARY_DIR}/path_to_dextool
)
