# vim: filetype=cmake

set(SRC_FILES
    ${CMAKE_SOURCE_DIR}/source/dextool/cachetools.d
    ${CMAKE_SOURCE_DIR}/source/dextool/clang.d
    ${CMAKE_SOURCE_DIR}/source/dextool/compilation_db/package.d
    ${CMAKE_SOURCE_DIR}/source/dextool/compilation_db/system_compiler.d
    ${CMAKE_SOURCE_DIR}/source/dextool/compilation_db/user_filerange.d
    ${CMAKE_SOURCE_DIR}/source/dextool/from.d
    ${CMAKE_SOURCE_DIR}/source/dextool/fsm.d
    ${CMAKE_SOURCE_DIR}/source/dextool/hash.d
    ${CMAKE_SOURCE_DIR}/source/dextool/io.d
    ${CMAKE_SOURCE_DIR}/source/dextool/nullable.d
    ${CMAKE_SOURCE_DIR}/source/dextool/set.d
    ${CMAKE_SOURCE_DIR}/source/dextool/type.d
    ${CMAKE_SOURCE_DIR}/source/dextool/user_filerange.d
    ${CMAKE_SOURCE_DIR}/source/dextool/utility.d
    ${CMAKE_SOURCE_DIR}/source/dextool/xml.d
    )

set(flags "-I${CMAKE_SOURCE_DIR}/source -I${CMAKE_SOURCE_DIR}/libs/clang/source -I${CMAKE_SOURCE_DIR}/libs/libclang/source -J${CMAKE_SOURCE_DIR}/libs/clang/resources -I${CMAKE_SOURCE_DIR}/vendor/blob_model/source")

compile_d_static_lib(dextool_dextool
    "${SRC_FILES}"
    "${flags}"
    ""
    "dextool_cpptooling")

add_dependencies(dextool_dextool dextool_embedded_version)

list(APPEND SRC_FILES "${CMAKE_SOURCE_DIR}/source/dextool/ut_main.d")
compile_d_unittest(dextool_dextool
    "${SRC_FILES}"
    "${flags}"
    ""
    "dextool_cpptooling;dextool_libclang")
