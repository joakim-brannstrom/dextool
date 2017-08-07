# vim: filetype=cmake

set(SRC_FILES
    ${CMAKE_SOURCE_DIR}/source/test/clang_util.d
    ${CMAKE_SOURCE_DIR}/source/test/helpers.d

    ${CMAKE_SOURCE_DIR}/source/test/component/scratch.d

    ${CMAKE_SOURCE_DIR}/source/test/component/analyzer/cpp_class_visitor.d
    ${CMAKE_SOURCE_DIR}/source/test/component/analyzer/test_clang.d
    ${CMAKE_SOURCE_DIR}/source/test/component/analyzer/type.d
    ${CMAKE_SOURCE_DIR}/source/test/component/analyzer/utility.d

    ${CMAKE_CURRENT_LIST_DIR}/ut_main.d
)

set(flags "-I${CMAKE_SOURCE_DIR}/source -I${CMAKE_SOURCE_DIR}/clang -I${CMAKE_SOURCE_DIR}/libclang -I${CMAKE_SOURCE_DIR}/dsrcgen/source -J${CMAKE_SOURCE_DIR}/clang/resources")

compile_d_unittest(component "${SRC_FILES}" "${flags}" "${LIBCLANG_LDFLAGS}" "dextool_cpptooling")
