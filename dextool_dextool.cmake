# vim: filetype=cmake

set(SRC_FILES
    ${CMAKE_SOURCE_DIR}/source/dextool/cli_help.d
    ${CMAKE_SOURCE_DIR}/source/dextool/compilation_db.d
    ${CMAKE_SOURCE_DIR}/source/dextool/hash.d
    ${CMAKE_SOURCE_DIR}/source/dextool/io.d
    ${CMAKE_SOURCE_DIR}/source/dextool/logger_conf.d
    ${CMAKE_SOURCE_DIR}/source/dextool/logger.d
    ${CMAKE_SOURCE_DIR}/source/dextool/type.d
    ${CMAKE_SOURCE_DIR}/source/dextool/utility.d
    ${CMAKE_SOURCE_DIR}/source/dextool/xml.d
    )

compile_d_static_lib(dextool_dextool "${SRC_FILES}" "" "" "")

add_dependencies(dextool_dextool dextool_embedded_version)

list(APPEND SRC_FILES "${CMAKE_SOURCE_DIR}/source/dextool/ut_main.d")
compile_d_unittest(dextool_dextool "${SRC_FILES}" "" "" "")
