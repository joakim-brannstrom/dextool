# vim: filetype=cmake

set(flags "-I${CMAKE_CURRENT_LIST_DIR}/taggedalgebraic/source")
file(GLOB_RECURSE SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/taggedalgebraic/source/*.d)

compile_d_static_lib(
    dextool_taggedalgebraic
    "${SRC_FILES}"
    "${flags}"
    ""
    ""
)
