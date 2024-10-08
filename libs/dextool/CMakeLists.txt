# vim: filetype=cmake

set(SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/source/dextool/cachetools.d
    ${CMAKE_CURRENT_LIST_DIR}/source/dextool/clang.d
    ${CMAKE_CURRENT_LIST_DIR}/source/dextool/compilation_db/package.d
    ${CMAKE_CURRENT_LIST_DIR}/source/dextool/compilation_db/system_compiler.d
    ${CMAKE_CURRENT_LIST_DIR}/source/dextool/compilation_db/user_filerange.d
    ${CMAKE_CURRENT_LIST_DIR}/source/dextool/io.d
    ${CMAKE_CURRENT_LIST_DIR}/source/dextool/type.d
    ${CMAKE_CURRENT_LIST_DIR}/source/dextool/utility.d
    ${CMAKE_CURRENT_LIST_DIR}/source/dextool/xml.d
    )

set(flags "-I${CMAKE_SOURCE_DIR}/source
-I${CMAKE_SOURCE_DIR}/libs/clang/source
${LIBCLANG_INC}
-I${CMAKE_SOURCE_DIR}/libs/libclang_ast/source
-I${CMAKE_SOURCE_DIR}/vendor/blob_model/source
-I${CMAKE_SOURCE_DIR}/vendor/mylib/source
-I${CMAKE_SOURCE_DIR}/vendor/sumtype/src
-I${CMAKE_SOURCE_DIR}/vendor/colorlog/source
-I${CMAKE_SOURCE_DIR}/vendor/undead/src
")

compile_d_static_lib(dextool_dextool
    "${SRC_FILES}"
    "${flags}"
    ""
    "dextool_libclang_ast;dextool_mylib;dextool_colorlog")

add_dependencies(dextool_dextool dextool_embedded_version)

list(APPEND SRC_FILES "${CMAKE_CURRENT_LIST_DIR}/ut_main.d")
compile_d_unittest(dextool_dextool
    "${SRC_FILES}"
    "${flags}"
    "${LIBCLANG_LDFLAGS} ${LIBCLANG_LIBS}"
    "dextool_cpptooling;dextool_libclang;dextool_colorlog")
