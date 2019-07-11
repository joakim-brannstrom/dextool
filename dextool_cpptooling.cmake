# vim: filetype=cmake

set(SRC_FILES
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/package.d

    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/analyze_helper.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/check_parse_result.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/context.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/cursor_backtrack.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/cursor_logger.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/cursor_visitor.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/include_visitor.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/package.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/store.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/type.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/type_logger.d

    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/ast/attribute.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/ast/base_visitor.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/ast/declaration.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/ast/directive.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/ast/expression.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/ast/extra.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/ast/node.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/ast/nodes.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/ast/package.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/ast/preprocessor.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/ast/reference.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/ast/statement.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/ast/translationunit.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/ast/tree.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/analyzer/clang/ast/visitor.d

    ${CMAKE_SOURCE_DIR}/source/cpptooling/data/class_classification.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/data/class_merge.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/data/package.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/data/representation.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/data/type.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/data/kind.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/data/kind_type.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/data/kind_type_format.d

    ${CMAKE_SOURCE_DIR}/source/cpptooling/data/symbol/container.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/data/symbol/package.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/data/symbol/types.d

    ${CMAKE_SOURCE_DIR}/source/cpptooling/generator/classes.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/generator/func.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/generator/gmock.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/generator/gtest.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/generator/includes.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/generator/utility.d

    ${CMAKE_SOURCE_DIR}/source/cpptooling/testdouble/header_filter.d

    ${CMAKE_SOURCE_DIR}/source/cpptooling/utility/dedup.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/utility/global_unique.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/utility/package.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/utility/sort.d
    ${CMAKE_SOURCE_DIR}/source/cpptooling/utility/virtualfilesystem.d
)

set(flags "-I${CMAKE_SOURCE_DIR}/source -I${CMAKE_SOURCE_DIR}/clang -I${CMAKE_SOURCE_DIR}/libs/libclang/source -I${CMAKE_SOURCE_DIR}/dsrcgen/source -J${CMAKE_SOURCE_DIR}/clang/resources -I${CMAKE_SOURCE_DIR}/vendor/taggedalgebraic/source -I${CMAKE_SOURCE_DIR}/vendor/blob_model/source")

compile_d_static_lib(dextool_cpptooling
    "${SRC_FILES}"
    "${flags}"
    ""
    "dextool_clang;dextool_dextool;dextool_dsrcgen;dextool_libclang;dextool_taggedalgebraic;dextool_blob_model")

list(APPEND SRC_FILES "${CMAKE_SOURCE_DIR}/source/cpptooling/ut_main.d")
compile_d_unittest(dextool_cpptooling "${SRC_FILES}" "${flags}" "" "dextool_clang;dextool_dextool;dextool_libclang;dextool_dsrcgen;dextool_blob_model")
