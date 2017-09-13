# vim: filetype=cmake

file(GLOB SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/external_main.d
    ${CMAKE_CURRENT_LIST_DIR}/c_tests.d
    ${CMAKE_CURRENT_LIST_DIR}/graphml_tests.d
    ${CMAKE_CURRENT_LIST_DIR}/plantuml_tests.d
)

set(flags "-I${CMAKE_SOURCE_DIR}/test/scriptlike/src -I${CMAKE_SOURCE_DIR}/test/source")

# Setup expected test environment around the integration test binary
execute_process(
    COMMAND ${CMAKE_SOURCE_DIR}/symlink.sh ${CMAKE_CURRENT_LIST_DIR}/fused_gmock ${CMAKE_BINARY_DIR}/fused_gmock
    COMMAND ${CMAKE_SOURCE_DIR}/symlink.sh ${CMAKE_CURRENT_LIST_DIR}/testdata ${CMAKE_BINARY_DIR}/testdata
)
