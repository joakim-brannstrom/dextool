# vim: filetype=cmake

# Local installation of unit-threaded

set(UNIT_THREADED_IMPORT "-I${CMAKE_CURRENT_LIST_DIR}/unit-threaded/source -I${CMAKE_CURRENT_LIST_DIR}/unit-threaded/subpackages/assertions/source -I${CMAKE_CURRENT_LIST_DIR}/unit-threaded/subpackages/exception/source -I${CMAKE_CURRENT_LIST_DIR}/unit-threaded/subpackages/from/source -I${CMAKE_CURRENT_LIST_DIR}/unit-threaded/subpackages/integration/source -I${CMAKE_CURRENT_LIST_DIR}/unit-threaded/subpackages/mocks/source -I${CMAKE_CURRENT_LIST_DIR}/unit-threaded/subpackages/property/source -I${CMAKE_CURRENT_LIST_DIR}/unit-threaded/subpackages/runner/source" CACHE INTERNAL "UNIT_THREADED_IMPORT")

file(GLOB SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/unit-threaded/source/unit_threaded/*.d
    ${CMAKE_CURRENT_LIST_DIR}/unit-threaded/subpackages/assertions/source/unit_threaded/*.d
    ${CMAKE_CURRENT_LIST_DIR}/unit-threaded/subpackages/exception/source/unit_threaded/*.d
    ${CMAKE_CURRENT_LIST_DIR}/unit-threaded/subpackages/from/source/unit_threaded/*.d
    ${CMAKE_CURRENT_LIST_DIR}/unit-threaded/subpackages/integration/source/unit_threaded/*.d
    ${CMAKE_CURRENT_LIST_DIR}/unit-threaded/subpackages/mocks/source/unit_threaded/*.d
    ${CMAKE_CURRENT_LIST_DIR}/unit-threaded/subpackages/property/source/unit_threaded/*.d
    ${CMAKE_CURRENT_LIST_DIR}/unit-threaded/subpackages/property/source/unit_threaded/randomized/*.d
    ${CMAKE_CURRENT_LIST_DIR}/unit-threaded/subpackages/runner/source/unit_threaded/runner/*.d
)

compile_d_static_lib(dextool_unit_threaded "${SRC_FILES}" "${UNIT_THREADED_IMPORT}" "" "")
