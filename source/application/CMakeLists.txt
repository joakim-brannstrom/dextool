# vim: filetype=cmake

file(GLOB SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/*.d)
set(SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/app.d
    ${CMAKE_CURRENT_LIST_DIR}/app_main.d
    ${CMAKE_CURRENT_LIST_DIR}/plugin.d
)

set(flags "-I${CMAKE_SOURCE_DIR}/source")

build_d_executable(
    "${DEXTOOL_MAIN_EXE}"
    "${SRC_FILES}"
    "${flags}"
    ""
    "dextool_dextool"
)

if(UNIX AND NOT APPLE)
add_custom_command(
    TARGET ${DEXTOOL_MAIN_EXE}
    POST_BUILD
    COMMAND cp --reflink=auto ${CMAKE_CURRENT_BINARY_DIR}/${DEXTOOL_MAIN_EXE} ${CMAKE_BINARY_DIR}/${DEXTOOL_MAIN_EXE}
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
)
elseif(UNIX AND APPLE)
add_custom_command(
    TARGET ${DEXTOOL_MAIN_EXE}
    POST_BUILD
    COMMAND cp ${CMAKE_CURRENT_BINARY_DIR}/${DEXTOOL_MAIN_EXE} ${CMAKE_BINARY_DIR}/${DEXTOOL_MAIN_EXE}
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
)
endif()

install(TARGETS ${DEXTOOL_MAIN_EXE} DESTINATION ${CMAKE_INSTALL_PREFIX}/bin)

list(APPEND SRC_FILES "${CMAKE_CURRENT_LIST_DIR}/ut_main.d")
compile_d_unittest(${DEXTOOL_MAIN_EXE} "${SRC_FILES}" "${flags}" "" "dextool_dextool")
