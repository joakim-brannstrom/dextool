# vim: filetype=cmake

file(GLOB SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/source/dextool/plugin/*.d)

set(flags "-I${CMAKE_SOURCE_DIR}/source")

compile_d_static_lib(dextool_plugin_utility "${SRC_FILES}" "${flags}" "" "dextool_dextool")

list(APPEND SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/source/ut_main.d)
compile_d_unittest(dextool_plugin_utility "${SRC_FILES}" "${flags}" "${LIBCLANG_LDFLAGS}" "dextool_dextool")
