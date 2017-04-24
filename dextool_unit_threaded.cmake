# vim: filetype=cmake

# Local installation of unit-threaded

file(GLOB SRC_FILES
    ${CMAKE_SOURCE_DIR}/unit-threaded/source/unit_threaded/*.d
    ${CMAKE_SOURCE_DIR}/unit-threaded/source/unit_threaded/property/*.d
    ${CMAKE_SOURCE_DIR}/unit-threaded/source/unit_threaded/randomized/*.d
)

compile_d_static_lib(dextool_unit_threaded "${SRC_FILES}" "" "" "")
