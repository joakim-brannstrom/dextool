# vim: filetype=cmake

set(SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/source/libclang_ast/check_parse_result.d
    ${CMAKE_CURRENT_LIST_DIR}/source/libclang_ast/context.d
    ${CMAKE_CURRENT_LIST_DIR}/source/libclang_ast/cursor_logger.d
    ${CMAKE_CURRENT_LIST_DIR}/source/libclang_ast/include_visitor.d
    ${CMAKE_CURRENT_LIST_DIR}/source/libclang_ast/cursor_visitor.d

    ${CMAKE_CURRENT_LIST_DIR}/source/libclang_ast/ast/attribute.d
    ${CMAKE_CURRENT_LIST_DIR}/source/libclang_ast/ast/base_visitor.d
    ${CMAKE_CURRENT_LIST_DIR}/source/libclang_ast/ast/declaration.d
    ${CMAKE_CURRENT_LIST_DIR}/source/libclang_ast/ast/directive.d
    ${CMAKE_CURRENT_LIST_DIR}/source/libclang_ast/ast/expression.d
    ${CMAKE_CURRENT_LIST_DIR}/source/libclang_ast/ast/extra.d
    ${CMAKE_CURRENT_LIST_DIR}/source/libclang_ast/ast/node.d
    ${CMAKE_CURRENT_LIST_DIR}/source/libclang_ast/ast/nodes.d
    ${CMAKE_CURRENT_LIST_DIR}/source/libclang_ast/ast/package.d
    ${CMAKE_CURRENT_LIST_DIR}/source/libclang_ast/ast/preprocessor.d
    ${CMAKE_CURRENT_LIST_DIR}/source/libclang_ast/ast/reference.d
    ${CMAKE_CURRENT_LIST_DIR}/source/libclang_ast/ast/statement.d
    ${CMAKE_CURRENT_LIST_DIR}/source/libclang_ast/ast/translationunit.d
    ${CMAKE_CURRENT_LIST_DIR}/source/libclang_ast/ast/tree.d
    ${CMAKE_CURRENT_LIST_DIR}/source/libclang_ast/ast/visitor.d
)

set(flags "-I${CMAKE_CURRENT_LIST_DIR}/source
-I${CMAKE_SOURCE_DIR}/libs/clang/source
-I${CMAKE_SOURCE_DIR}/libs/libclang/source
-I${CMAKE_SOURCE_DIR}/vendor/blob_model/source
-I${CMAKE_SOURCE_DIR}/vendor/mylib/source
-I${CMAKE_SOURCE_DIR}/vendor/sumtype/src
-J${CMAKE_SOURCE_DIR}/libs/clang/resources
")

compile_d_static_lib(dextool_libclang_ast
    "${SRC_FILES}"
    "${flags}"
    ""
    "dextool_clang;dextool_libclang;dextool_blob_model;dextool_mylib;dextool_sumtype")

#list(APPEND SRC_FILES "${CMAKE_CURRENT_LIST_DIR}/ut_main.d")
#compile_d_unittest(dextool_cpptooling "${SRC_FILES}" "${flags}" "" "dextool_clang;dextool_dextool;dextool_libclang;dextool_dsrcgen;dextool_blob_model;dextool_mylib;dextool_sumtype")

#add_subdirectory(test)
