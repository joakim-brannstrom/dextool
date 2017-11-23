# vim: filetype=cmake

# Local installation of unit-threaded

file(GLOB SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/unit-threaded/source/unit_threaded/*.d
    ${CMAKE_CURRENT_LIST_DIR}/unit-threaded/source/unit_threaded/property/*.d
    ${CMAKE_CURRENT_LIST_DIR}/unit-threaded/source/unit_threaded/randomized/*.d
)

compile_d_static_lib(dextool_unit_threaded "${SRC_FILES}" "" "" "")
