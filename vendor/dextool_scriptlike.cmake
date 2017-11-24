# vim: filetype=cmake

file(GLOB_RECURSE SCRIPTLIKE_FILES
    ${CMAKE_CURRENT_LIST_DIR}/scriptlike/src/*.d
)

compile_d_static_lib(dextool_scriptlike "${SCRIPTLIKE_FILES}" "" "" "")
