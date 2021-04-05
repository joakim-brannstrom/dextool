# vim: filetype=cmake

set(SRC_FILES
    ${CMAKE_CURRENT_LIST_DIR}/clang_util.d

    ${CMAKE_CURRENT_LIST_DIR}/component/scratch.d

    ${CMAKE_CURRENT_LIST_DIR}/component/generator.d

    ${CMAKE_CURRENT_LIST_DIR}/component/analyzer/cpp_class_visitor.d
    ${CMAKE_CURRENT_LIST_DIR}/component/analyzer/test_clang.d
    ${CMAKE_CURRENT_LIST_DIR}/component/analyzer/type.d
    ${CMAKE_CURRENT_LIST_DIR}/component/analyzer/utility.d

    ${CMAKE_CURRENT_LIST_DIR}/ut_main.d
)

set(flags "-I${CMAKE_SOURCE_DIR}/source
-I${CMAKE_SOURCE_DIR}/libs/clang/source
-I${CMAKE_SOURCE_DIR}/libs/cpptooling/source
-I${CMAKE_SOURCE_DIR}/libs/dextool/source
-I${CMAKE_SOURCE_DIR}/libs/dsrcgen/source
-I${CMAKE_SOURCE_DIR}/libs/libclang/source
-I${CMAKE_SOURCE_DIR}/libs/libclang_ast/source
-I${CMAKE_SOURCE_DIR}/vendor/blob_model/source
-I${CMAKE_SOURCE_DIR}/vendor/mylib/source
-I${CMAKE_SOURCE_DIR}/vendor/sumtype/src
-J${CMAKE_SOURCE_DIR}/libs/clang/resources
")

compile_d_unittest(component "${SRC_FILES}" "${flags}" "" "dextool_cpptooling;dextool_libclang_ast;dextool_blob_model;dextool_mylib;dextool_sumtype")
