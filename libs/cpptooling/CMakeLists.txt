# vim: filetype=cmake

set(SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/analyzer/package.d

    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/analyzer/clang/analyze_helper.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/analyzer/clang/cursor_backtrack.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/analyzer/clang/package.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/analyzer/clang/store.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/analyzer/clang/type.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/analyzer/clang/type_logger.d

    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/data/class_classification.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/data/class_merge.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/data/package.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/data/representation.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/data/type.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/data/kind.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/data/kind_type.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/data/kind_type_format.d

    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/data/symbol/container.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/data/symbol/package.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/data/symbol/types.d

    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/generator/classes.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/generator/func.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/generator/gmock.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/generator/gtest.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/generator/includes.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/generator/utility.d

    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/testdouble/header_filter.d

    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/utility/dedup.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/utility/global_unique.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/utility/package.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/utility/sort.d
    ${CMAKE_CURRENT_LIST_DIR}/source/cpptooling/utility/virtualfilesystem.d
)

set(flags "-I${CMAKE_CURRENT_LIST_DIR}/source
-I${CMAKE_SOURCE_DIR}/libs/clang/source
-I${CMAKE_SOURCE_DIR}/libs/dextool/source
-I${CMAKE_SOURCE_DIR}/libs/dsrcgen/source
-I${CMAKE_SOURCE_DIR}/libs/libclang/source
-I${CMAKE_SOURCE_DIR}/libs/libclang_ast/source
-I${CMAKE_SOURCE_DIR}/vendor/blob_model/source
-I${CMAKE_SOURCE_DIR}/vendor/mylib/source
-I${CMAKE_SOURCE_DIR}/vendor/sumtype/src
-J${CMAKE_SOURCE_DIR}/libs/clang/resources
")

compile_d_static_lib(dextool_cpptooling
    "${SRC_FILES}"
    "${flags}"
    ""
    "dextool_clang;dextool_dextool;dextool_libclang_ast;dextool_dsrcgen;dextool_libclang;dextool_blob_model;dextool_mylib;dextool_sumtype")

list(APPEND SRC_FILES "${CMAKE_CURRENT_LIST_DIR}/ut_main.d")
compile_d_unittest(dextool_cpptooling "${SRC_FILES}" "${flags}" "" "dextool_clang;dextool_dextool;dextool_libclang_ast;dextool_libclang;dextool_dsrcgen;dextool_blob_model;dextool_mylib;dextool_sumtype")

add_subdirectory(test)
