# vim: filetype=cmake

set(SRC_FILES
    ${CMAKE_SOURCE_DIR}/source/test/clang_util.d

    ${CMAKE_SOURCE_DIR}/source/test/component/scratch.d

    ${CMAKE_SOURCE_DIR}/source/test/component/generator.d

    ${CMAKE_SOURCE_DIR}/source/test/component/analyzer/cpp_class_visitor.d
    ${CMAKE_SOURCE_DIR}/source/test/component/analyzer/test_clang.d
    ${CMAKE_SOURCE_DIR}/source/test/component/analyzer/type.d
    ${CMAKE_SOURCE_DIR}/source/test/component/analyzer/utility.d

    ${CMAKE_CURRENT_LIST_DIR}/ut_main.d
)

set(flags "-I${CMAKE_SOURCE_DIR}/source -I${CMAKE_SOURCE_DIR}/libs/clang/source -I${CMAKE_SOURCE_DIR}/libs/libclang/source -I${CMAKE_SOURCE_DIR}/dsrcgen/source -J${CMAKE_SOURCE_DIR}/libs/clang/resources -I${CMAKE_SOURCE_DIR}/vendor/taggedalgebraic/source -I${CMAKE_SOURCE_DIR}/vendor/blob_model/source")

compile_d_unittest(component "${SRC_FILES}" "${flags}" "" "dextool_cpptooling;dextool_blob_model")
