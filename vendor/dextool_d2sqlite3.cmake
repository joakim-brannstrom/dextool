# vim: filetype=cmake

# Requires: sqlite3
find_library(found_sqlite3_path NAMES sqlite3)
get_filename_component(sqlite_lib_name ${found_sqlite3_path} NAME)
get_filename_component(sqlite_lib_dir ${found_sqlite3_path} DIRECTORY)

set(SQLITE3_LIB "-L${sqlite_lib_dir} -l:${sqlite_lib_name}" CACHE STRING "Flags to link with a sqlite3 library (example: -L/usr/lib -lsqlite3)")
message(STATUS "sqlite3 found: ${SQLITE3_LIB}")

set(flags "-I${CMAKE_CURRENT_LIST_DIR}/d2sqlite3/source -version=SqliteEnableColumnMetadata -version=SqliteEnableUnlockNotify")
file(GLOB_RECURSE SRC_FILES ${CMAKE_CURRENT_LIST_DIR}/d2sqlite3/source/d2sqlite3/*.d)

compile_d_static_lib(
    dextool_d2sqlite3
    "${SRC_FILES}"
    "${flags}"
    ""
    ""
)
target_link_libraries(dextool_d2sqlite3 ${SQLITE3_LIB})

compile_d_unittest(
    dextool_d2sqlite3_tests
    "${CMAKE_CURRENT_LIST_DIR}/d2sqlite3/source/tests.d;${SRC_FILES};"
    "${flags} -main"
    ""
    "${SQLITE3_LIB}"
)
